import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision

public protocol ContextCapturing {
    func capture() throws -> (CapturedContext, Data?)
}

public final class ContextCaptureService: ContextCapturing {
    private let maxDepth = 14
    private let maxNodeCount = 9_000
    private let maxLineCount = 12_000
    private let captureTimeoutSeconds: TimeInterval = 4.0
    private let prioritizedTextAttributes = [
        "AXTitle",
        "AXValue",
        "AXDescription",
        "AXHelp",
        "AXDocument",
        "AXURL",
        "AXLabel",
        "AXPlaceholderValue",
        "AXRoleDescription",
        "AXSelectedText",
        "AXFilename",
        "AXIdentifier"
    ]
    private let prioritizedChildAttributes = [
        "AXChildren",
        "AXContents",
        "AXVisibleChildren",
        "AXWindows",
        "AXMainWindow",
        "AXFocusedWindow",
        "AXFocusedUIElement",
        "AXRows",
        "AXColumns",
        "AXCells",
        "AXSelectedRows",
        "AXSelectedChildren",
        "AXTabs",
        "AXUIElements",
        "AXGroups",
        "AXOutlineRows",
        "AXMenuBar"
    ]
    private let ignoredAttributes: Set<String> = [
        "AXParent",
        "AXTopLevelUIElement",
        "AXWindow",
        "AXPosition",
        "AXSize",
        "AXFrame",
        "AXMinimized",
        "AXFocused",
        "AXSelectedTextRange",
        "AXSelectedTextRanges",
        "AXVisibleCharacterRange",
        "AXStartTextMarker",
        "AXEndTextMarker"
    ]

    public init() {}

    public func capture() throws -> (CapturedContext, Data?) {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            throw AppError.noFrontmostApp
        }

        let appName = frontmostApp.localizedName ?? "Unknown App"
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? "unknown.bundle"
        let sourceType: SourceType = bundleIdentifier.contains("Safari")
            || bundleIdentifier.contains("Chrome")
            || bundleIdentifier.contains("Firefox")
            || bundleIdentifier.contains("Arc")
            ? .browserTab
            : .desktopApp

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        let focusedWindow = elementAttribute(from: appElement, attribute: kAXFocusedWindowAttribute as String)
        let focusedElement = elementAttribute(from: appElement, attribute: kAXFocusedUIElementAttribute as String)
        let windowTitle =
            stringAttribute(from: focusedWindow, attribute: kAXTitleAttribute as String)
            ?? stringAttribute(from: focusedElement, attribute: kAXTitleAttribute as String)
            ?? "Unknown Window"

        let accessibilityText = extractAccessibilityText(
            appElement: appElement,
            focusedWindow: focusedWindow,
            focusedElement: focusedElement
        )

        let screenshot = captureFrontWindowImage(for: frontmostApp.processIdentifier) ?? CGDisplayCreateImage(CGMainDisplayID())
        let ocrText =
            screenshot.flatMap { try? recognizeText(in: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        let captureMethod: CaptureMethod
        switch (!accessibilityText.isEmpty, !ocrText.isEmpty) {
        case (true, true):
            captureMethod = .hybrid
        case (true, false):
            captureMethod = .accessibility
        case (false, true):
            captureMethod = .screenshotOCR
        default:
            captureMethod = .none
        }

        let combinedText = combinedContent(
            appName: appName,
            windowTitle: windowTitle,
            accessibilityText: accessibilityText,
            ocrText: ocrText
        )
        let processingDurationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000.0)
        let diagnostics = CaptureDiagnostics(
            accessibilityLineCount: accessibilityText.components(separatedBy: "\n").filter { !$0.isEmpty }.count,
            ocrLineCount: ocrText.components(separatedBy: "\n").filter { !$0.isEmpty }.count,
            processingDurationMs: processingDurationMs,
            usedFallbackOCR: !ocrText.isEmpty
        )

        let pngData = screenshot.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }

        return (
            CapturedContext(
                sourceType: sourceType,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                captureMethod: captureMethod,
                accessibilityText: accessibilityText,
                ocrText: ocrText,
                combinedText: combinedText,
                diagnostics: diagnostics
            ),
            pngData
        )
    }

    private func combinedContent(
        appName: String,
        windowTitle: String,
        accessibilityText: String,
        ocrText: String
    ) -> String {
        if accessibilityText.isEmpty && ocrText.isEmpty {
            return [
                "No readable content was captured.",
                "App: \(appName)",
                "Window: \(windowTitle)",
                "Verify Accessibility and Screen Recording permissions."
            ].joined(separator: "\n")
        }

        if !accessibilityText.isEmpty && !ocrText.isEmpty {
            return [
                "Accessibility Capture",
                accessibilityText,
                "",
                "OCR Capture",
                ocrText
            ].joined(separator: "\n")
        }

        if !accessibilityText.isEmpty {
            return accessibilityText
        }

        return ocrText
    }

    private func extractAccessibilityText(
        appElement: AXUIElement,
        focusedWindow: AXUIElement?,
        focusedElement: AXUIElement?
    ) -> String {
        var lines: [String] = []
        var visited: Set<Int> = []
        var nodeCount = 0
        let deadline = Date().addingTimeInterval(captureTimeoutSeconds)

        var roots: [AXUIElement] = []

        if let focusedElement {
            roots.append(focusedElement)
        }

        if let focusedWindow {
            roots.append(focusedWindow)
        }

        if let mainWindow = elementAttribute(from: appElement, attribute: "AXMainWindow") {
            roots.append(mainWindow)
        }

        roots.append(contentsOf: elementArrayAttribute(from: appElement, attribute: "AXWindows"))

        if let menuBar = elementAttribute(from: appElement, attribute: "AXMenuBar") {
            roots.append(menuBar)
        }

        roots.append(appElement)

        for root in roots {
            if Date() >= deadline || nodeCount >= maxNodeCount || lines.count >= maxLineCount {
                break
            }

            collectText(
                from: root,
                depth: 0,
                visited: &visited,
                nodeCount: &nodeCount,
                lines: &lines,
                deadline: deadline
            )
        }

        return deduplicatedLines(lines).joined(separator: "\n")
    }

    private func collectText(
        from element: AXUIElement,
        depth: Int,
        visited: inout Set<Int>,
        nodeCount: inout Int,
        lines: inout [String],
        deadline: Date
    ) {
        if
            Date() >= deadline
            || depth > maxDepth
            || nodeCount >= maxNodeCount
            || lines.count >= maxLineCount
        {
            return
        }

        let elementHash = Int(CFHash(element))
        if !visited.insert(elementHash).inserted {
            return
        }

        nodeCount += 1

        let discoveredAttributes = attributeNames(from: element)
        var orderedAttributes: [String] = []
        var seenAttributes: Set<String> = []

        for attribute in prioritizedTextAttributes + prioritizedChildAttributes {
            if discoveredAttributes.contains(attribute), !ignoredAttributes.contains(attribute) {
                orderedAttributes.append(attribute)
                seenAttributes.insert(attribute)
            }
        }

        for attribute in discoveredAttributes where !ignoredAttributes.contains(attribute) && !seenAttributes.contains(attribute) {
            orderedAttributes.append(attribute)
        }

        for attribute in orderedAttributes {
            guard let value = attributeValue(from: element, attribute: attribute) else {
                continue
            }

            appendLines(from: value, lines: &lines)

            if Date() >= deadline || lines.count >= maxLineCount {
                return
            }

            for child in elements(from: value) {
                collectText(
                    from: child,
                    depth: depth + 1,
                    visited: &visited,
                    nodeCount: &nodeCount,
                    lines: &lines,
                    deadline: deadline
                )

                if Date() >= deadline || lines.count >= maxLineCount || nodeCount >= maxNodeCount {
                    return
                }
            }
        }
    }

    private func captureFrontWindowImage(for pid: pid_t) -> CGImage? {
        guard let windowID = frontWindowID(for: pid) else {
            return nil
        }

        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    private func frontWindowID(for pid: pid_t) -> CGWindowID? {
        guard
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return nil
        }

        let targetPID = Int(pid)

        for window in windowInfo {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int, ownerPID == targetPID else {
                continue
            }

            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            if
                let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                (bounds.width < 80 || bounds.height < 60)
            {
                continue
            }

            guard let windowNumber = window[kCGWindowNumber as String] as? UInt32 else {
                continue
            }

            return CGWindowID(windowNumber)
        }

        return nil
    }

    private func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let lines =
            request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .map { normalizedString($0) }
            .filter { !$0.isEmpty }
            ?? []

        return deduplicatedLines(lines).joined(separator: "\n")
    }

    private func attributeValue(from element: AXUIElement, attribute: String) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }
        return value
    }

    private func elementAttribute(from element: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = attributeValue(from: element, attribute: attribute) else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func elementArrayAttribute(from element: AXUIElement, attribute: String) -> [AXUIElement] {
        guard let value = attributeValue(from: element, attribute: attribute) else {
            return []
        }

        return elements(from: value)
    }

    private func attributeNames(from element: AXUIElement) -> [String] {
        var namesRef: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &namesRef)
        guard result == .success, let namesRef else {
            return []
        }

        return namesRef as? [String] ?? []
    }

    private func stringAttribute(from element: AXUIElement?, attribute: String) -> String? {
        guard let element, let value = attributeValue(from: element, attribute: attribute) else {
            return nil
        }

        let string = string(from: value)
        if string.isEmpty {
            return nil
        }

        return string
    }

    private func string(from value: AnyObject) -> String {
        if let text = value as? String {
            return normalizedString(text)
        }

        if let attributedText = value as? NSAttributedString {
            return normalizedString(attributedText.string)
        }

        if let url = value as? URL {
            return normalizedString(url.absoluteString)
        }

        if let number = value as? NSNumber {
            return normalizedString(number.stringValue)
        }

        return ""
    }

    private func appendLines(from value: AnyObject, lines: inout [String]) {
        let singleLine = string(from: value)
        if !singleLine.isEmpty {
            lines.append(singleLine)
        }

        if let array = value as? [Any] {
            for item in array {
                guard let typedItem = item as AnyObject? else {
                    continue
                }

                let line = string(from: typedItem)
                if !line.isEmpty {
                    lines.append(line)
                }
            }
        }
    }

    private func elements(from value: AnyObject) -> [AXUIElement] {
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [value as! AXUIElement]
        }

        guard let array = value as? [Any] else {
            return []
        }

        var output: [AXUIElement] = []

        for item in array {
            guard let itemObject = item as AnyObject? else {
                continue
            }

            if CFGetTypeID(itemObject) == AXUIElementGetTypeID() {
                output.append(itemObject as! AXUIElement)
            }
        }

        return output
    }

    private func deduplicatedLines(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []

        for line in lines {
            let normalized = normalizedString(line)
            if normalized.isEmpty || seen.contains(normalized) {
                continue
            }

            seen.insert(normalized)
            output.append(normalized)
        }

        return output
    }

    private func normalizedString(_ raw: String) -> String {
        let collapsed = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
