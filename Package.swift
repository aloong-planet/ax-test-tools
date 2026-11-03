// swift-tools-version: 6.0
import PackageDescription

let package = Package(name: "AXTestTools", platforms: [.macOS(.v14)], products: [
    .executable(name: "AXRunner", targets: ["AXRunner"])
], targets: [
    .target(name: "AXScenario"),
    .executableTarget(name: "AXRunner", dependencies: ["AXScenario"]),
    .testTarget(name: "AXScenarioTests", dependencies: ["AXScenario"])
])
