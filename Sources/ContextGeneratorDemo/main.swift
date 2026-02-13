import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision

struct CapturedContext: Codable {
    let id: UUID
    let capturedAt: Date
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String
    let captureMethod: String
    let accessibilityText: String
    let ocrText: String
    let combinedText: String

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var clipboardText: String {
        [
            "Captured at: \(Self.timestampFormatter.string(from: capturedAt))",
            "App: \(appName)",
            "Bundle ID: \(bundleIdentifier)",
            "Window: \(windowTitle)",
            "Method: \(captureMethod)",
            "",
            combinedText
        ].joined(separator: "\n")
    }
}

enum CaptureError: LocalizedError {
    case noFrontmostApp

    var errorDescription: String? {
        switch self {
        case .noFrontmostApp:
            return "No frontmost app found."
        }
    }
}

final class ContextStorage {
    let directoryURL: URL
    let jsonURL: URL
    let textURL: URL
    let screenshotURL: URL

    init() {
        let baseURL =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        directoryURL = baseURL.appendingPathComponent("ContextGeneratorDemo", isDirectory: true)
        jsonURL = directoryURL.appendingPathComponent("latest-context.json")
        textURL = directoryURL.appendingPathComponent("latest-context.txt")
        screenshotURL = directoryURL.appendingPathComponent("latest-screenshot.png")

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func save(context: CapturedContext, screenshot: CGImage?) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(context).write(to: jsonURL, options: .atomic)
        try context.clipboardText.write(to: textURL, atomically: true, encoding: .utf8)

        if let screenshot, let data = Self.pngData(from: screenshot) {
            try data.write(to: screenshotURL, options: .atomic)
        }
    }

    func loadLatest() -> CapturedContext? {
        guard let data = try? Data(contentsOf: jsonURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CapturedContext.self, from: data)
    }

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

final class ContextCaptureService {
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

    func capture() throws -> (CapturedContext, CGImage?) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            throw CaptureError.noFrontmostApp
        }

        let appName = frontmostApp.localizedName ?? "Unknown App"
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? "unknown.bundle"
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

        let captureMethod: String
        switch (!accessibilityText.isEmpty, !ocrText.isEmpty) {
        case (true, true):
            captureMethod = "hybrid"
        case (true, false):
            captureMethod = "accessibility"
        case (false, true):
            captureMethod = "screenshot_ocr"
        default:
            captureMethod = "none"
        }

        let combinedText = combinedContent(
            appName: appName,
            windowTitle: windowTitle,
            accessibilityText: accessibilityText,
            ocrText: ocrText
        )

        return (
            CapturedContext(
                id: UUID(),
                capturedAt: Date(),
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                captureMethod: captureMethod,
                accessibilityText: accessibilityText,
                ocrText: ocrText,
                combinedText: combinedText
            ),
            screenshot
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

        for attribute in discoveredAttributes {
            if ignoredAttributes.contains(attribute) || seenAttributes.contains(attribute) {
                continue
            }

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

        var elements: [AXUIElement] = []

        for item in array {
            guard let itemObject = item as AnyObject? else {
                continue
            }

            if CFGetTypeID(itemObject) == AXUIElementGetTypeID() {
                elements.append(itemObject as! AXUIElement)
            }
        }

        return elements
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

final class MenuBarAppController: NSObject, NSApplicationDelegate {
    private let captureService = ContextCaptureService()
    private let storage = ContextStorage()
    private var lastCapturedContext: CapturedContext?

    private var statusItem: NSStatusItem?
    private var stateMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private var copyMenuItem = NSMenuItem(title: "Copy Last Context", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestPermissionsOnLaunch()
        lastCapturedContext = storage.loadLatest()
        copyMenuItem.isEnabled = (lastCapturedContext != nil)
        updateStatus(lastCapturedContext == nil ? "Ready" : "Loaded latest context")
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Ctx"

        let menu = NSMenu()

        stateMenuItem.isEnabled = false
        menu.addItem(stateMenuItem)
        menu.addItem(.separator())

        let captureItem = NSMenuItem(
            title: "Capture Context",
            action: #selector(captureContext),
            keyEquivalent: "c"
        )
        captureItem.target = self
        menu.addItem(captureItem)

        copyMenuItem.action = #selector(copyLastContext)
        copyMenuItem.keyEquivalent = "y"
        copyMenuItem.target = self
        copyMenuItem.isEnabled = false
        menu.addItem(copyMenuItem)

        let openFolderItem = NSMenuItem(
            title: "Open Saved Files",
            action: #selector(openSavedFiles),
            keyEquivalent: "o"
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func requestPermissionsOnLaunch() {
        let accessibilityOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)

        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
        }
    }

    @objc private func captureContext() {
        updateStatus("Capturing...")
        copyMenuItem.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (context, screenshot) = try self.captureService.capture()
                try self.storage.save(context: context, screenshot: screenshot)

                DispatchQueue.main.async {
                    self.lastCapturedContext = context
                    self.copyMenuItem.isEnabled = true
                    self.updateStatus("Captured from \(context.appName)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateStatus("Capture failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func copyLastContext() {
        if lastCapturedContext == nil {
            lastCapturedContext = storage.loadLatest()
        }

        guard let context = lastCapturedContext else {
            updateStatus("No saved context yet")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context.clipboardText, forType: .string)
        updateStatus("Copied to clipboard")
    }

    @objc private func openSavedFiles() {
        NSWorkspace.shared.open(storage.directoryURL)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatus(_ text: String) {
        stateMenuItem.title = text
    }
}

let app = NSApplication.shared
let delegate = MenuBarAppController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
