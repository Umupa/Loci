// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "Loci",
  platforms: [.macOS(.v26)],
  targets: [
    .target(name: "LociModel", swiftSettings: strict),
    .target(name: "LociUI", dependencies: ["LociModel"], swiftSettings: strict),
    .executableTarget(name: "Loci", dependencies: ["LociUI"], swiftSettings: strict),
    .testTarget(name: "LociModelTests", dependencies: ["LociModel"], swiftSettings: strict),
    .testTarget(name: "LociUITests", dependencies: ["LociUI"], swiftSettings: strict),
    .testTarget(name: "ArchitectureTests", swiftSettings: strict),
  ]
)
