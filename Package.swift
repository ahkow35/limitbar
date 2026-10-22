// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LimitBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LimitBar", targets: ["LimitBar"])],
    targets: [
        .target(name: "LimitBarCore"),
        .executableTarget(name: "LimitBar", dependencies: ["LimitBarCore"], resources: [.process("Resources")]),
        .testTarget(name: "LimitBarCoreTests", dependencies: ["LimitBarCore"])
    ],
    swiftLanguageVersions: [.v5]
)
