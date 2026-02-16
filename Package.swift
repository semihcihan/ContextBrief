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
            name: "ContextBriefApp",
            targets: ["ContextBriefApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0")
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
            name: "ContextBriefApp",
            dependencies: [
                "ContextGenerator",
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk")
            ],
            path: "Sources/ContextGeneratorApp",
            resources: [
                .copy("Resources/GoogleService-Info.plist")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "ContextGeneratorTests",
            dependencies: ["ContextGenerator", "ContextBriefApp"],
            path: "Tests/ContextGeneratorTests"
        )
    ]
)
