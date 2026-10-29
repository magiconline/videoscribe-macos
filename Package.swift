// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VideoScribe", platforms: [.macOS(.v14)], products: [
    .library(name: "VideoScribeCore", targets: ["VideoScribeCore"]),
    .executable(name: "VideoScribe", targets: ["VideoScribe"]),
    .executable(name: "VideoScribeAgent", targets: ["VideoScribeAgent"])
], targets: [
    .target(name: "VideoScribeCore"),
    .executableTarget(name: "VideoScribe", dependencies: ["VideoScribeCore"]),
    .executableTarget(name: "VideoScribeAgent", dependencies: ["VideoScribeCore"]),
    .testTarget(name: "VideoScribeTests", dependencies: ["VideoScribe", "VideoScribeCore"])
], swiftLanguageModes: [.v5])
