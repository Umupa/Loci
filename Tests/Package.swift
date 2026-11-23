// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LociChecks",
  platforms: [.macOS(.v26)],
  targets: [
    .testTarget(name: "ArchitectureTests", path: "ArchitectureTests", swiftSettings: [.treatAllWarnings(as: .error)])
  ]
)
