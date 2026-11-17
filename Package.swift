// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "Loci",
  defaultLocalization: "en",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    .package(url: "https://github.com/gonzalezreal/textual.git", exact: "0.5.0"),
    .package(url: "https://github.com/yukihiratype2/swift-highlight.git", exact: "0.1.1"),
    .package(url: "https://github.com/mgriebling/SwiftMath.git", exact: "1.7.3"),
  ],
  targets: [
    .target(name: "LociModel", swiftSettings: strict),
    .target(
      name: "LociStore",
      dependencies: [
        "LociModel", .product(name: "Yams", package: "Yams"), .product(name: "GRDB", package: "GRDB.swift"),
      ],
      swiftSettings: strict),
    .target(
      name: "LociAgents", dependencies: ["LociModel"], resources: [.copy("Resources")], swiftSettings: strict),
    .target(
      name: "LociHost", dependencies: ["LociModel", "LociStore", "LociAgents"], resources: [.copy("Resources")],
      swiftSettings: strict),
    .target(
      name: "LociUI",
      dependencies: [
        "LociModel", .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "Textual", package: "textual"),
        .product(name: "HighlightSwift", package: "swift-highlight"),
        .product(name: "SwiftMath", package: "SwiftMath"),
      ],
      resources: [.process("Resources")], swiftSettings: strict),
    .executableTarget(name: "LociEval", dependencies: ["LociModel", "LociHost", "LociAgents"], swiftSettings: strict),
    .executableTarget(name: "Loci", dependencies: ["LociModel", "LociUI", "LociHost"], swiftSettings: strict),
    .testTarget(name: "LociModelTests", dependencies: ["LociModel"], swiftSettings: strict),
    .testTarget(name: "LociStoreTests", dependencies: ["LociStore"], swiftSettings: strict),
    .testTarget(
      name: "LociAgentsTests", dependencies: ["LociAgents"], resources: [.copy("Fixtures")], swiftSettings: strict),
    .testTarget(name: "LociHostTests", dependencies: ["LociHost", "LociStore", "LociAgents"], swiftSettings: strict),
    .testTarget(name: "LociUITests", dependencies: ["LociUI"], swiftSettings: strict),
    .testTarget(name: "LociEvalTests", dependencies: ["LociEval", "LociModel"], swiftSettings: strict),
    .testTarget(name: "ArchitectureTests", swiftSettings: strict),
  ]
)
