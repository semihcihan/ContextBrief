import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision

public protocol ContextCapturing {
    func capture() throws -> (CapturedSnapshot, Data?)
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
    private let browserContentRoles: Set<String> = [
        "AXWebArea",
        "AXDocument"
    ]
    private let browserMainContentRoles: Set<String> = [
        "AXLandmarkMain"
    ]
    private let browserChromeExactLines: Set<String> = [
        "accessibility capture",
        "ocr capture",
        "back",
        "forward",
        "reload",
        "share",
        "home",
        "new tab",
        "tab search",
        "downloads",
        "extensions",
        "show sidebar",
        "hide sidebar",
        "bookmarks",
        "bookmark this tab",
        "reader"
    ]
    private let browserChromeContainsPhrases: [String] = [
        "address and search bar",
        "search or enter address",
        "smart search field",
        "go back",
        "go forward",
        "open location",
        "show bookmarks bar",
        "hide bookmarks bar"
    ]
    private let browserMetadataExactLines: Set<String> = [
        "html content",
        "link",
        "text",
        "group",
        "item",
        "parent",
        "child",
        "children",
        "button",
        "heading",
        "navigation",
        "global",
        "source",
        "column",
        "hierarchy",
        "content list",
        "list marker",
        "decorated-title",
        "has-adjacent-elements",
        "relationships-item",
        "relationships-list",
        "conditional-constraints"
    ]
    private let browserMetadataContainsPhrases: [String] = [
        " in page link",
        "start of code block",
        "end of code block",
        "router-link",
        "nav-menu",
        "ac-gn-",
        "axlandmark",
        "axapplicationgroup",
        "apple-documentation-nav",
        "documentation-nav"
    ]
    private let repeatedBoilerplateKeywords: [String] = [
        "privacy",
        "terms",
        "cookie",
        "cookies",
        "all rights reserved",
        "copyright"
    ]
    private let mustKeepKeywords: [String] = [
        "error",
        "failure",
        "failed",
        "warning",
        "denied",
        "timeout",
        "forbidden",
        "unauthorized",
        "invalid",
        "required",
        "success",
        "completed",
        "saved",
        "exception",
        "fatal",
        "unavailable",
        "retry",
        "quota"
    ]
    private let browserBundleKeywords = [
        "safari",
        "chrome",
        "firefox",
        "arc"
    ]
    private let webViewHeavyBundleKeywords = [
        "slack",
        "teams",
        "notion",
        "electron",
        "discord"
    ]

    private enum AppCaptureCategory: String {
        case browser
        case webViewHeavy
        case nativeApp
    }

    private enum AccessibilitySignalQuality: String {
        case high
        case medium
        case low
    }

    private struct OCRDecision {
        let shouldCapture: Bool
        let reason: String
    }

    private struct BrowserFilteringMetrics {
        let baselineLineCount: Int
        let filteredLineCount: Int
        let removedLineCount: Int
        let removedByRule: [String: Int]
        let anchorCount: Int
        let missingAnchorCount: Int
        let usedFilteredCapture: Bool
        let appliedCarryover: Bool
        let fallbackReasons: [String]
    }

    private struct CombinedCaptureSections {
        let accessibilityLines: [String]
        let ocrLines: [String]
    }

    public init() {}

    public func capture() throws -> (CapturedSnapshot, Data?) {
        let startTime = CFAbsoluteTimeGetCurrent()
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            throw AppError.noFrontmostApp
        }
        guard frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw AppError.captureTargetIsContextBrief
        }

        let appName = frontmostApp.localizedName ?? "Unknown App"
        let bundleIdentifier = frontmostApp.bundleIdentifier ?? "unknown.bundle"
        let captureCategory = appCaptureCategory(for: bundleIdentifier)
        let sourceType: SourceType = captureCategory == .browser ? .browserTab : .desktopApp

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
            focusedElement: focusedElement,
            includeAppChromeRoots: captureCategory == .nativeApp
        )
        let accessibilityLines = normalizedLines(from: accessibilityText)
        let accessibilityQuality = accessibilitySignalQuality(for: accessibilityLines)
        let tabContentRawLines: [String]
        if captureCategory == .browser || captureCategory == .webViewHeavy {
            tabContentRawLines = extractCurrentTabAccessibilityLines(
                appElement: appElement,
                focusedWindow: focusedWindow,
                focusedElement: focusedElement,
                deduplicate: false
            )
        } else {
            tabContentRawLines = []
        }
        let tabContentLines = deduplicatedLines(tabContentRawLines)
        let ocrDecision = ocrDecision(
            for: captureCategory,
            accessibilityQuality: accessibilityQuality,
            accessibilityLines: accessibilityLines,
            hasContentRoot: !tabContentLines.isEmpty
        )
        AppLogger.debug(
            "OCR decision [category=\(captureCategory.rawValue) accessibilityQuality=\(accessibilityQuality.rawValue) accessibilityLineCount=\(accessibilityLines.count) hasContentRoot=\(!tabContentLines.isEmpty) shouldCaptureOCR=\(ocrDecision.shouldCapture) reason=\(ocrDecision.reason)]"
        )

        let screenshot = captureFrontWindowImage(for: frontmostApp.processIdentifier)
        let ocrText: String
        if ocrDecision.shouldCapture {
            if screenshot == nil {
                AppLogger.debug(
                    "OCR capture unavailable [category=\(captureCategory.rawValue) reason=noFrontWindowImage]"
                )
            }
            ocrText =
                screenshot.flatMap { try? recognizeText(in: $0) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
        } else {
            ocrText = ""
        }

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
        let filteredCombinedText: String?
        if sourceType == .browserTab {
            let (filteredText, metrics) = filteredBrowserCombinedText(
                appElement: appElement,
                focusedWindow: focusedWindow,
                focusedElement: focusedElement,
                baselineCombinedText: combinedText,
                preExtractedTabLines: tabContentLines,
                preExtractedTabRawLines: tabContentRawLines
            )
            logBrowserFilteringMetrics(metrics)
            filteredCombinedText = filteredText
        } else {
            filteredCombinedText = filteredCombinedTextForNonBrowser(
                accessibilityText: accessibilityText,
                ocrText: ocrText
            )
        }
        let processingDurationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000.0)
        let diagnostics = CaptureDiagnostics(
            accessibilityLineCount: accessibilityText.components(separatedBy: "\n").filter { !$0.isEmpty }.count,
            ocrLineCount: ocrText.components(separatedBy: "\n").filter { !$0.isEmpty }.count,
            processingDurationMs: processingDurationMs,
            usedFallbackOCR: !ocrText.isEmpty
        )

        let pngData = screenshot.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }

        return (
            CapturedSnapshot(
                sourceType: sourceType,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                captureMethod: captureMethod,
                accessibilityText: accessibilityText,
                ocrText: ocrText,
                combinedText: combinedText,
                filteredCombinedText: filteredCombinedText,
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

    private func filteredBrowserCombinedText(
        appElement: AXUIElement,
        focusedWindow: AXUIElement?,
        focusedElement: AXUIElement?,
        baselineCombinedText: String,
        preExtractedTabLines: [String]? = nil,
        preExtractedTabRawLines: [String]? = nil
    ) -> (String?, BrowserFilteringMetrics) {
        let baselineLines = normalizedLines(from: baselineCombinedText)
        guard !baselineLines.isEmpty else {
            return (
                nil,
                BrowserFilteringMetrics(
                    baselineLineCount: 0,
                    filteredLineCount: 0,
                    removedLineCount: 0,
                    removedByRule: [:],
                    anchorCount: 0,
                    missingAnchorCount: 0,
                    usedFilteredCapture: false,
                    appliedCarryover: false,
                    fallbackReasons: ["emptyBaseline"]
                )
            )
        }

        let sections = parseCombinedCaptureSections(from: baselineCombinedText)
        let accessibilityLines = sections.accessibilityLines.isEmpty
            ? baselineLines
            : sections.accessibilityLines
        let tabRawLines = preExtractedTabRawLines ?? extractCurrentTabAccessibilityLines(
            appElement: appElement,
            focusedWindow: focusedWindow,
            focusedElement: focusedElement,
            deduplicate: false
        )
        let tabLines = preExtractedTabLines ?? deduplicatedLines(tabRawLines)
        let candidateSeedLines = tabLines.isEmpty
            ? accessibilityLines
            : tabLines
        let candidateSeedLinesForFrequency = tabRawLines.isEmpty
            ? accessibilityLines
            : tabRawLines
        let mustKeepLines = deduplicatedLines(baselineLines.filter(isMustKeepBrowserLine))
        let protectedLines = Set(mustKeepLines)
        let lineFrequency = frequencies(for: candidateSeedLinesForFrequency)

        var fallbackReasons: [String] = []
        var removedByRule: [String: Int] = [:]
        var filteredLines = filterBrowserLines(
            candidateSeedLines,
            protectedLines: protectedLines,
            frequencies: lineFrequency,
            removedByRule: &removedByRule
        )

        let shouldAugmentWithOCR = shouldAugmentWithOCR(
            primaryLines: filteredLines,
            tabLines: tabLines
        )
        if shouldAugmentWithOCR, !sections.ocrLines.isEmpty {
            let ocrFrequencies = frequencies(for: sections.ocrLines)
            let ocrFilteredLines = filterBrowserLines(
                sections.ocrLines,
                protectedLines: protectedLines,
                frequencies: ocrFrequencies,
                removedByRule: &removedByRule
            ).filter { isLikelyMeaningfulOCRLine($0) || containsMustKeepKeyword(in: $0.lowercased()) }
            removedByRule["ocrSectionExcluded", default: 0] += max(0, sections.ocrLines.count - ocrFilteredLines.count)
            if !ocrFilteredLines.isEmpty {
                filteredLines = deduplicatedLines(filteredLines + ocrFilteredLines)
                fallbackReasons.append("ocrAugmented")
            } else {
                fallbackReasons.append("ocrAugmentNoUsefulLines")
            }
        } else if !sections.ocrLines.isEmpty {
            removedByRule["ocrSectionExcluded", default: 0] += sections.ocrLines.count
        }

        let filteredLineSet = Set(filteredLines)
        let missingMustKeepLines = mustKeepLines.filter { !filteredLineSet.contains($0) }
        let finalLines = deduplicatedLines(filteredLines + missingMustKeepLines)

        let usedFilteredCapture: Bool
        let filteredCombinedText: String?
        if finalLines.isEmpty {
            fallbackReasons.append("filteredEmpty")
            usedFilteredCapture = false
            filteredCombinedText = nil
        } else {
            usedFilteredCapture = true
            filteredCombinedText = finalLines.joined(separator: "\n")
        }
        if tabLines.isEmpty {
            fallbackReasons.append("noTabContentRoot")
        }

        let metrics = BrowserFilteringMetrics(
            baselineLineCount: baselineLines.count,
            filteredLineCount: finalLines.count,
            removedLineCount: max(0, baselineLines.count - finalLines.count),
            removedByRule: removedByRule,
            anchorCount: mustKeepLines.count,
            missingAnchorCount: missingMustKeepLines.count,
            usedFilteredCapture: usedFilteredCapture,
            appliedCarryover: !missingMustKeepLines.isEmpty,
            fallbackReasons: fallbackReasons
        )
        return (filteredCombinedText, metrics)
    }

    private func filteredCombinedTextForNonBrowser(
        accessibilityText: String,
        ocrText: String
    ) -> String? {
        let accessibilityLines = normalizedLines(from: accessibilityText)
        let ocrLines = normalizedLines(from: ocrText)
        guard !ocrLines.isEmpty else {
            return nil
        }
        if accessibilityLines.isEmpty {
            return ocrLines.joined(separator: "\n")
        }
        guard !hasLikelyMeaningfulContent(accessibilityLines) else {
            return nil
        }
        let meaningfulOCRLines = deduplicatedLines(
            ocrLines.filter { isLikelyMeaningfulOCRLine($0) || containsMustKeepKeyword(in: $0.lowercased()) }
        )
        guard !meaningfulOCRLines.isEmpty else {
            return nil
        }
        AppLogger.debug(
            "Non-browser OCR fallback selected [accessibilityLineCount=\(accessibilityLines.count) ocrLineCount=\(ocrLines.count) selectedLineCount=\(meaningfulOCRLines.count)]"
        )
        return meaningfulOCRLines.joined(separator: "\n")
    }

    private func logBrowserFilteringMetrics(_ metrics: BrowserFilteringMetrics) {
        let removedByRuleSummary = metrics.removedByRule
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let fallbackReasonSummary = metrics.fallbackReasons.joined(separator: ",")
        AppLogger.debug(
            "Browser capture filtering [baselineLineCount=\(metrics.baselineLineCount) filteredLineCount=\(metrics.filteredLineCount) removedLineCount=\(metrics.removedLineCount) removedByRule=\(removedByRuleSummary) anchorCount=\(metrics.anchorCount) missingAnchorCount=\(metrics.missingAnchorCount) usedFilteredCapture=\(metrics.usedFilteredCapture) appliedCarryover=\(metrics.appliedCarryover) fallbackReasons=\(fallbackReasonSummary)]"
        )
    }

    private func extractCurrentTabAccessibilityText(
        appElement: AXUIElement,
        focusedWindow: AXUIElement?,
        focusedElement: AXUIElement?
    ) -> String {
        extractCurrentTabAccessibilityLines(
            appElement: appElement,
            focusedWindow: focusedWindow,
            focusedElement: focusedElement,
            deduplicate: true
        ).joined(separator: "\n")
    }

    private func extractCurrentTabAccessibilityLines(
        appElement: AXUIElement,
        focusedWindow: AXUIElement?,
        focusedElement: AXUIElement?,
        deduplicate: Bool
    ) -> [String] {
        var roots: [AXUIElement] = []
        if let focusedElement {
            roots.append(contentsOf: browserContentRoots(startingAt: focusedElement))
        }
        if let focusedWindow {
            roots.append(contentsOf: browserContentRoots(startingAt: focusedWindow))
        }
        if let mainWindow = elementAttribute(from: appElement, attribute: "AXMainWindow") {
            roots.append(contentsOf: browserContentRoots(startingAt: mainWindow))
        }

        let uniqueRoots = deduplicatedElements(roots)
        guard !uniqueRoots.isEmpty else {
            return []
        }
        let preferredRoots = preferredBrowserContentRoots(from: uniqueRoots)

        var lines: [String] = []
        var visited: Set<Int> = []
        var nodeCount = 0
        let deadline = Date().addingTimeInterval(captureTimeoutSeconds)

        for root in preferredRoots {
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
        if deduplicate {
            return deduplicatedLines(lines)
        }
        return normalizedNonEmptyLines(lines)
    }

    private func browserContentRoots(startingAt root: AXUIElement) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited: Set<Int> = []
        var contentRoots: [AXUIElement] = []
        let maxSearchDepth = 10
        let maxSearchNodes = 1_500

        while !queue.isEmpty && visited.count < maxSearchNodes {
            let (current, depth) = queue.removeFirst()
            let hash = Int(CFHash(current))
            if !visited.insert(hash).inserted {
                continue
            }

            let role = stringAttribute(from: current, attribute: kAXRoleAttribute as String) ?? ""
            if browserContentRoles.contains(role) {
                contentRoots.append(current)
                continue
            }
            if depth >= maxSearchDepth {
                continue
            }

            for child in childElementsForBrowserRootSearch(from: current) {
                queue.append((child, depth + 1))
            }
        }

        return contentRoots
    }

    private func preferredBrowserContentRoots(from roots: [AXUIElement]) -> [AXUIElement] {
        let mainRoots = roots.flatMap { root in
            descendantElements(
                startingAt: root,
                matchingRoles: browserMainContentRoles,
                maxDepth: 8,
                maxNodes: 2_000
            )
        }
        let deduplicatedMainRoots = deduplicatedElements(mainRoots)
        return deduplicatedMainRoots.isEmpty
            ? roots
            : deduplicatedMainRoots
    }

    private func descendantElements(
        startingAt root: AXUIElement,
        matchingRoles roles: Set<String>,
        maxDepth: Int,
        maxNodes: Int
    ) -> [AXUIElement] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited: Set<Int> = []
        var matches: [AXUIElement] = []

        while !queue.isEmpty && visited.count < maxNodes {
            let (current, depth) = queue.removeFirst()
            let hash = Int(CFHash(current))
            if !visited.insert(hash).inserted {
                continue
            }

            let role = stringAttribute(from: current, attribute: kAXRoleAttribute as String) ?? ""
            if roles.contains(role) {
                matches.append(current)
            }
            if depth >= maxDepth {
                continue
            }
            for child in childElementsForBrowserRootSearch(from: current) {
                queue.append((child, depth + 1))
            }
        }

        return matches
    }

    private func childElementsForBrowserRootSearch(from element: AXUIElement) -> [AXUIElement] {
        let discoveredAttributes = attributeNames(from: element)
        var output: [AXUIElement] = []
        for attribute in discoveredAttributes where !ignoredAttributes.contains(attribute) {
            if
                !prioritizedChildAttributes.contains(attribute)
                && !attribute.hasSuffix("Children")
                && !attribute.hasSuffix("Contents")
                && !attribute.hasSuffix("UIElements")
            {
                continue
            }
            guard let value = attributeValue(from: element, attribute: attribute) else {
                continue
            }
            output.append(contentsOf: elements(from: value))
        }
        return output
    }

    private func browserNoiseRule(for line: String, frequencies: [String: Int]) -> String? {
        let normalized = line.lowercased()
        if browserChromeExactLines.contains(normalized) {
            return "knownChromeControl"
        }
        if browserChromeContainsPhrases.contains(where: { normalized.contains($0) }) {
            return "chromePhrase"
        }
        if browserMetadataExactLines.contains(normalized) {
            return "metadataLabel"
        }
        if browserMetadataContainsPhrases.contains(where: { normalized.contains($0) }) {
            return "metadataPhrase"
        }
        if isAXRoleToken(line) {
            return "axRoleToken"
        }
        if isLikelyMetadataIdentifierLine(normalized) {
            return "identifierToken"
        }
        if normalized.rangeOfCharacter(from: .letters) == nil {
            return "nonTextToken"
        }
        if
            frequencies[normalized, default: 0] > 1,
            repeatedBoilerplateKeywords.contains(where: { normalized.contains($0) }),
            !isMustKeepBrowserLine(line)
        {
            return "repeatedBoilerplate"
        }
        return nil
    }

    private func isMustKeepBrowserLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        if isAXRoleToken(line) || isLikelyMetadataIdentifierLine(normalized) {
            return false
        }
        if containsMustKeepKeyword(in: normalized) {
            return true
        }
        if
            normalized.rangeOfCharacter(from: .decimalDigits) != nil,
            normalized.contains(":"),
            normalized.contains(" ")
        {
            return true
        }
        if
            normalized.rangeOfCharacter(from: .decimalDigits) != nil,
            normalized.rangeOfCharacter(from: .letters) != nil,
            normalized.contains(" ")
        {
            return true
        }
        if normalized.contains("|"), normalized.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        return false
    }

    private func parseCombinedCaptureSections(from combinedText: String) -> CombinedCaptureSections {
        let rawLines = combinedText.components(separatedBy: "\n")
        guard
            let accessibilityHeaderIndex = rawLines.firstIndex(where: { normalizedString($0).lowercased() == "accessibility capture" }),
            let ocrHeaderIndex = rawLines.firstIndex(where: { normalizedString($0).lowercased() == "ocr capture" }),
            accessibilityHeaderIndex < ocrHeaderIndex
        else {
            return CombinedCaptureSections(
                accessibilityLines: normalizedNonEmptyLines(rawLines),
                ocrLines: []
            )
        }
        let accessibilityLines = normalizedNonEmptyLines(
            Array(rawLines[(accessibilityHeaderIndex + 1) ..< ocrHeaderIndex])
        )
        let ocrLines = normalizedNonEmptyLines(
            Array(rawLines[(ocrHeaderIndex + 1) ..< rawLines.count])
        )
        return CombinedCaptureSections(
            accessibilityLines: accessibilityLines,
            ocrLines: ocrLines
        )
    }

    private func containsMustKeepKeyword(in normalizedLine: String) -> Bool {
        let words = Set(
            normalizedLine.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        return mustKeepKeywords.contains(where: { words.contains($0) })
    }

    private func isURLLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.hasPrefix("http://") || normalized.hasPrefix("https://")
    }

    private func isInPageURLLine(_ line: String) -> Bool {
        let normalized = normalizedString(line)
        guard let components = URLComponents(string: normalized) else {
            return normalized.contains("#")
        }
        guard let fragment = components.fragment, !fragment.isEmpty else {
            return false
        }
        if fragment.hasPrefix("/") || fragment.hasPrefix("!") || fragment.contains("/") {
            return false
        }
        let hasMeaningfulPath = !components.path.isEmpty && components.path != "/"
        let hasQuery = !(components.queryItems?.isEmpty ?? true)
        return !hasMeaningfulPath && !hasQuery
    }

    private func isAXRoleToken(_ line: String) -> Bool {
        let normalized = normalizedString(line)
        guard normalized.hasPrefix("AX"), !normalized.contains(" ") else {
            return false
        }
        let remainder = normalized.dropFirst(2)
        guard !remainder.isEmpty else {
            return false
        }
        return remainder.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private func isLikelyMetadataIdentifierLine(_ normalizedLine: String) -> Bool {
        if normalizedLine.contains("://") {
            return false
        }
        if normalizedLine.range(of: "^[a-z0-9]+(?:[-_][a-z0-9]+)+$", options: .regularExpression) != nil {
            return true
        }
        if normalizedLine.hasPrefix("ac-") || normalizedLine.hasPrefix("nav-") || normalizedLine.hasPrefix("router-") {
            return true
        }
        return false
    }

    private func filterBrowserLines(
        _ lines: [String],
        protectedLines: Set<String>,
        frequencies: [String: Int],
        removedByRule: inout [String: Int]
    ) -> [String] {
        var filteredLines: [String] = []
        var keptPrimaryURL = false
        for line in lines {
            if protectedLines.contains(line) {
                filteredLines.append(line)
                continue
            }
            if isURLLine(line) {
                if isInPageURLLine(line) {
                    removedByRule["inPageURL", default: 0] += 1
                    continue
                }
                if keptPrimaryURL {
                    removedByRule["secondaryURL", default: 0] += 1
                    continue
                }
                keptPrimaryURL = true
                filteredLines.append(line)
                continue
            }
            if let rule = browserNoiseRule(for: line, frequencies: frequencies) {
                removedByRule[rule, default: 0] += 1
                continue
            }
            filteredLines.append(line)
        }
        return deduplicatedLines(filteredLines)
    }

    private func appCaptureCategory(for bundleIdentifier: String) -> AppCaptureCategory {
        let normalizedBundleIdentifier = bundleIdentifier.lowercased()
        if browserBundleKeywords.contains(where: { normalizedBundleIdentifier.contains($0) }) {
            return .browser
        }
        if webViewHeavyBundleKeywords.contains(where: { normalizedBundleIdentifier.contains($0) }) {
            return .webViewHeavy
        }
        return .nativeApp
    }

    private func accessibilitySignalQuality(for lines: [String]) -> AccessibilitySignalQuality {
        let meaningfulLineCount = lines.filter { isLikelyMeaningfulTextLine($0) }.count
        let mustKeepLineCount = self.mustKeepLineCount(in: lines)
        if meaningfulLineCount >= 8 || (meaningfulLineCount >= 4 && mustKeepLineCount >= 1) {
            return .high
        }
        if meaningfulLineCount >= 3 {
            return .medium
        }
        return .low
    }

    private func mustKeepLineCount(in lines: [String]) -> Int {
        lines.reduce(into: 0) { result, line in
            if containsMustKeepKeyword(in: line.lowercased()) {
                result += 1
            }
        }
    }

    private func ocrDecision(
        for category: AppCaptureCategory,
        accessibilityQuality: AccessibilitySignalQuality,
        accessibilityLines: [String],
        hasContentRoot: Bool
    ) -> OCRDecision {
        if accessibilityLines.isEmpty {
            return OCRDecision(shouldCapture: true, reason: "emptyAccessibility")
        }
        switch accessibilityQuality {
        case .high:
            return OCRDecision(shouldCapture: false, reason: "highAccessibilitySignal")
        case .medium:
            if category == .nativeApp {
                return OCRDecision(shouldCapture: false, reason: "mediumSignalNativeApp")
            }
            if !hasContentRoot {
                return OCRDecision(shouldCapture: true, reason: "mediumSignalMissingContentRoot")
            }
            if mustKeepLineCount(in: accessibilityLines) == 0 {
                return OCRDecision(shouldCapture: true, reason: "mediumSignalNoMustKeepAnchors")
            }
            return OCRDecision(shouldCapture: false, reason: "mediumSignalSufficient")
        case .low:
            return OCRDecision(shouldCapture: true, reason: "lowAccessibilitySignal")
        }
    }

    private func shouldAugmentWithOCR(primaryLines: [String], tabLines: [String]) -> Bool {
        if tabLines.isEmpty || primaryLines.isEmpty {
            return true
        }
        return !hasLikelyMeaningfulContent(primaryLines)
    }

    private func hasLikelyMeaningfulContent(_ lines: [String]) -> Bool {
        for line in lines {
            let normalized = line.lowercased()
            if containsMustKeepKeyword(in: normalized) {
                return true
            }
            if isLikelyMeaningfulTextLine(line) {
                return true
            }
        }
        return false
    }

    private func isLikelyMeaningfulOCRLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        if containsMustKeepKeyword(in: normalized) {
            return true
        }
        return isLikelyMeaningfulTextLine(line)
    }

    private func isLikelyMeaningfulTextLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        if isURLLine(line) || isAXRoleToken(line) || isLikelyMetadataIdentifierLine(normalized) {
            return false
        }

        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 5 {
            return true
        }
        if words.count >= 3 {
            let longWordCount = words.filter { $0.count >= 4 }.count
            if longWordCount >= 2 {
                return true
            }
        }

        let hasLetters = normalized.rangeOfCharacter(from: .letters) != nil
        let hasDigits = normalized.rangeOfCharacter(from: .decimalDigits) != nil
        if hasLetters, hasDigits, normalized.contains(" ") {
            return true
        }
        if hasLetters, normalized.contains(" "), normalized.count >= 24 {
            return true
        }
        return false
    }

    private func wordCount(in normalizedLine: String) -> Int {
        normalizedLine.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }

    private func normalizedLines(from text: String) -> [String] {
        deduplicatedLines(text.components(separatedBy: "\n"))
    }

    private func normalizedNonEmptyLines(_ lines: [String]) -> [String] {
        lines.map(normalizedString).filter { !$0.isEmpty }
    }

    private func frequencies(for lines: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in lines {
            counts[line.lowercased(), default: 0] += 1
        }
        return counts
    }

    private func deduplicatedElements(_ elements: [AXUIElement]) -> [AXUIElement] {
        var seen: Set<Int> = []
        var output: [AXUIElement] = []
        for element in elements {
            let hash = Int(CFHash(element))
            if seen.insert(hash).inserted {
                output.append(element)
            }
        }
        return output
    }

    private func extractAccessibilityText(
        appElement: AXUIElement,
        focusedWindow: AXUIElement?,
        focusedElement: AXUIElement?,
        includeAppChromeRoots: Bool
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

        if includeAppChromeRoots {
            if let menuBar = elementAttribute(from: appElement, attribute: "AXMenuBar") {
                roots.append(menuBar)
            }
            roots.append(appElement)
        }

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
        performAXRead {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            guard result == .success, let value else {
                return nil
            }
            return value
        }
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
        performAXRead {
            var namesRef: CFArray?
            let result = AXUIElementCopyAttributeNames(element, &namesRef)
            guard result == .success, let namesRef else {
                return []
            }

            return namesRef as? [String] ?? []
        }
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

    private func performAXRead<T>(_ block: () -> T) -> T {
        block()
    }
}
