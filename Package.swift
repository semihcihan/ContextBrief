// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContextGeneratorDemo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ContextGenerator",
            targets: ["ContextGenerator"]
        ),
        .executable(
            name: "ContextGeneratorDemo",
            targets: ["ContextGeneratorDemo"]
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
            name: "ContextGeneratorDemo",
            dependencies: ["ContextGenerator"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "ContextGeneratorTests",
            dependencies: ["ContextGenerator"],
            path: "Tests/ContextGeneratorTests"
        )
    ]
)
