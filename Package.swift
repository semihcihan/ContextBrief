// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContextGenerator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ContextGenerator",
            targets: ["ContextGenerator"]
        ),
        .executable(
            name: "ContextGeneratorApp",
            targets: ["ContextGeneratorApp"]
        )
    ],
    targets: [
        .target(
            name: "ContextGenerator",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "ContextGeneratorApp",
            dependencies: ["ContextGenerator"],
            path: "Sources/ContextGeneratorApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "ContextGeneratorTests",
            dependencies: ["ContextGenerator", "ContextGeneratorApp"],
            path: "Tests/ContextGeneratorTests"
        )
    ]
)
