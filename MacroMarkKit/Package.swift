// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacroMarkKit",
    platforms: [
        .iOS("26.0"),
        .watchOS("11.0"),
        .macOS("14.0"),
    ],
    products: [
        .library(
            name: "MacroMarkKit",
            targets: ["MacroMarkKit"]
        ),
    ],
    targets: [
        .target(
            name: "MacroMarkKit"
        ),
        .testTarget(
            name: "MacroMarkKitTests",
            dependencies: ["MacroMarkKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
