// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "Loci",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
  ],
  targets: [
    .target(name: "LociModel", swiftSettings: strict),
    .target(
      name: "LociStore",
      dependencies: [
        "LociModel", .product(name: "Yams", package: "Yams"), .product(name: "GRDB", package: "GRDB.swift"),
      ],
      swiftSettings: strict),
    .target(name: "LociUI", dependencies: ["LociModel"], swiftSettings: strict),
    .executableTarget(name: "Loci", dependencies: ["LociUI"], swiftSettings: strict),
    .testTarget(name: "LociModelTests", dependencies: ["LociModel"], swiftSettings: strict),
    .testTarget(name: "LociStoreTests", dependencies: ["LociStore"], swiftSettings: strict),
    .testTarget(name: "LociUITests", dependencies: ["LociUI"], swiftSettings: strict),
    .testTarget(name: "ArchitectureTests", swiftSettings: strict),
  ]
)
