// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AEMotionExtensions",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "AEMotionExtensionsCore", targets: ["AEMotionExtensionsCore"]),
        .library(
            name: "AEMotionExtensionsHost",
            type: .dynamic,
            targets: ["AEMotionUI271Host", "AEMotionUI271Bootstrap"]
        ),
        .library(
            name: "AEMotionExtensionsLegacySource",
            type: .dynamic,
            targets: ["AEMotionExtensionsLegacySourceHost", "AEMotionLegacySourceBootstrap"]
        ),
    ],
    targets: [
        .target(name: "AEMotionExtensionsCore"),
        .target(
            name: "AEMotionExtensionsLegacySourceHost",
            dependencies: ["AEMotionExtensionsCore"],
            path: "Sources/AEMotionExtensionsHost"
        ),
        .target(
            name: "AEMotionLegacySourceBootstrap",
            dependencies: ["AEMotionExtensionsLegacySourceHost"],
            path: "Sources/AEMotionBootstrap",
            publicHeadersPath: "include"
        ),
        .target(name: "AEMotionUI271Host", dependencies: ["AEMotionExtensionsCore"]),
        .target(
            name: "AEMotionUI271Bootstrap",
            dependencies: ["AEMotionUI271Host"],
            publicHeadersPath: "include"
        ),
        .testTarget(name: "AEMotionExtensionsCoreTests", dependencies: ["AEMotionExtensionsCore"]),
    ]
)
