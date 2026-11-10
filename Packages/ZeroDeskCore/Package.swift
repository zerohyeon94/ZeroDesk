// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZeroDeskCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ZeroDeskCore", targets: ["ZeroDeskCore"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "ZeroDeskCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .testTarget(name: "ZeroDeskCoreTests", dependencies: ["ZeroDeskCore"], resources: [.copy("Fixtures")]),
    ]
)
