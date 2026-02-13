// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContextGeneratorDemo",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ContextGeneratorDemo",
            targets: ["ContextGeneratorDemo"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ContextGeneratorDemo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision")
            ]
        )
    ]
)
