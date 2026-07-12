// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AEMotionExtensions",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "AEMotionExtensionsCore", targets: ["AEMotionExtensionsCore"]),
        .library(name: "AEMotionExtensionsHost", type: .dynamic, targets: ["AEMotionExtensionsHost", "AEMotionBootstrap"]),
    ],
    targets: [
        .target(name: "AEMotionExtensionsCore"),
        .target(name: "AEMotionExtensionsHost", dependencies: ["AEMotionExtensionsCore"]),
        .target(name: "AEMotionBootstrap", dependencies: ["AEMotionExtensionsHost"], publicHeadersPath: "include"),
        .testTarget(name: "AEMotionExtensionsCoreTests", dependencies: ["AEMotionExtensionsCore"]),
    ]
)
