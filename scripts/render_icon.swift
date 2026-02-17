import AppKit
import Foundation
import WebKit

enum RenderIconError: LocalizedError {
    case invalidArguments(String)
    case timeout
    case navigationFailed(String)
    case snapshotFailed(String)
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .timeout:
            return "Timed out while rendering HTML icon."
        case .navigationFailed(let message):
            return "Failed to load HTML file: \(message)"
        case .snapshotFailed(let message):
            return "Failed to capture icon snapshot: \(message)"
        case .pngEncodingFailed:
            return "Failed to encode PNG from rendered snapshot."
        }
    }
}

struct RenderIconArguments {
    let inputURL: URL
    let outputURL: URL
    let size: Int

    static func parse() throws -> RenderIconArguments {
        var inputPath: String?
        var outputPath: String?
        var size = 1024
        var index = 1

        while index < CommandLine.arguments.count {
            let argument = CommandLine.arguments[index]
            switch argument {
            case "--input":
                index += 1
                guard index < CommandLine.arguments.count else {
                    throw RenderIconError.invalidArguments("Missing value for --input")
                }
                inputPath = CommandLine.arguments[index]
            case "--output":
                index += 1
                guard index < CommandLine.arguments.count else {
                    throw RenderIconError.invalidArguments("Missing value for --output")
                }
                outputPath = CommandLine.arguments[index]
            case "--size":
                index += 1
                guard index < CommandLine.arguments.count else {
                    throw RenderIconError.invalidArguments("Missing value for --size")
                }
                guard let parsed = Int(CommandLine.arguments[index]), parsed > 0 else {
                    throw RenderIconError.invalidArguments("Invalid --size value: \(CommandLine.arguments[index])")
                }
                size = parsed
            default:
                throw RenderIconError.invalidArguments("Unknown argument: \(argument)")
            }
            index += 1
        }

        guard let inputPath else {
            throw RenderIconError.invalidArguments("Missing required argument: --input")
        }
        guard let outputPath else {
            throw RenderIconError.invalidArguments("Missing required argument: --output")
        }

        return RenderIconArguments(
            inputURL: URL(fileURLWithPath: inputPath),
            outputURL: URL(fileURLWithPath: outputPath),
            size: size
        )
    }
}

final class HTMLIconRenderer: NSObject, WKNavigationDelegate {
    private let arguments: RenderIconArguments
    private var webView: WKWebView?
    private var completed = false
    private var failure: Error?

    init(arguments: RenderIconArguments) {
        self.arguments = arguments
    }

    func run() throws {
        guard FileManager.default.fileExists(atPath: arguments.inputURL.path) else {
            throw RenderIconError.invalidArguments("Input file not found: \(arguments.inputURL.path)")
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let size = CGFloat(arguments.size)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: size, height: size), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        view.loadFileURL(arguments.inputURL, allowingReadAccessTo: arguments.inputURL.deletingLastPathComponent())

        let timeoutAt = Date().addingTimeInterval(20)
        while !completed && Date() < timeoutAt {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if let failure {
            throw failure
        }
        if !completed {
            throw RenderIconError.timeout
        }
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: arguments.size, height: arguments.size)

            webView.takeSnapshot(with: configuration) { [self] image, error in
                if let error {
                    failure = RenderIconError.snapshotFailed(error.localizedDescription)
                    completed = true
                    return
                }

                guard
                    let image,
                    let tiff = image.tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: tiff),
                    let png = bitmap.representation(using: .png, properties: [:])
                else {
                    failure = RenderIconError.pngEncodingFailed
                    completed = true
                    return
                }

                do {
                    try FileManager.default.createDirectory(
                        at: arguments.outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try png.write(to: arguments.outputURL)
                    completed = true
                } catch {
                    failure = error
                    completed = true
                }
            }
        }
    }

    func webView(
        _: WKWebView,
        didFail _: WKNavigation!,
        withError error: Error
    ) {
        failure = RenderIconError.navigationFailed(error.localizedDescription)
        completed = true
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        failure = RenderIconError.navigationFailed(error.localizedDescription)
        completed = true
    }
}

do {
    let arguments = try RenderIconArguments.parse()
    let renderer = HTMLIconRenderer(arguments: arguments)
    try renderer.run()
    print("Rendered \(arguments.outputURL.path)")
} catch {
    fputs("render_icon.swift error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
