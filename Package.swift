// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AEMotionExtensions",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "AEMotionExtensionsCore", targets: ["AEMotionExtensionsCore"]),
        .library(
            name: "AEMotionUI272",
            type: .dynamic,
            targets: ["AEMotionUI271Host", "AEMotionUI271Bootstrap"]
        ),
        .library(
            name: "AEMotionExtensionsSourceSnapshot",
            type: .dynamic,
            targets: ["AEMotionExtensionsSourceHost", "AEMotionSourceBootstrap"]
        ),
    ],
    targets: [
        .target(name: "AEMotionExtensionsCore"),
        .target(
            name: "AEMotionExtensionsSourceHost",
            dependencies: ["AEMotionExtensionsCore"],
            path: "Sources/AEMotionExtensionsHost"
        ),
        .target(
            name: "AEMotionSourceBootstrap",
            dependencies: ["AEMotionExtensionsSourceHost"],
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
