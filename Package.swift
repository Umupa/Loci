// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "Loci",
  defaultLocalization: "en",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
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
        "LociModel", .product(name: "GRDB", package: "GRDB.swift"),
      ],
      swiftSettings: strict),
    .target(
      name: "LociAgents", dependencies: ["LociModel"], swiftSettings: strict),
    .binaryTarget(
      name: "whisper",
      url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
      checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"),
    .target(
      name: "LociMedia",
      dependencies: [
        "LociModel", "whisper", .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "FluidAudio", package: "FluidAudio"),
      ],
      resources: [.copy("Resources")],
      swiftSettings: strict),
    .target(name: "LociRemote", dependencies: ["LociModel"], swiftSettings: strict),
    .target(
      name: "LociHost", dependencies: ["LociModel", "LociStore", "LociAgents", "LociMedia", "LociRemote"],
      resources: [.copy("Resources")],
      swiftSettings: strict),
    .target(
      name: "LociUI",
      dependencies: [
        "LociModel", .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "Textual", package: "textual"),
        .product(name: "HighlightSwift", package: "swift-highlight"),
        .product(name: "SwiftMath", package: "SwiftMath"),
      ],
      resources: [.process("Resources"), .copy("Vendor/Mermaid")], swiftSettings: strict),
    .executableTarget(name: "Loci", dependencies: ["LociModel", "LociUI", "LociHost"], swiftSettings: strict),
    .executableTarget(name: "LociTool", dependencies: ["LociModel", "LociRemote"], swiftSettings: strict),
    .testTarget(name: "LociModelTests", dependencies: ["LociModel"], swiftSettings: strict),
    .testTarget(name: "LociStoreTests", dependencies: ["LociStore"], swiftSettings: strict),
    .testTarget(
      name: "LociAgentsTests", dependencies: ["LociAgents"], resources: [.copy("Fixtures")], swiftSettings: strict),
    .testTarget(
      name: "LociMediaTests", dependencies: ["LociMedia"], resources: [.copy("Fixtures")], swiftSettings: strict),
    .testTarget(
      name: "LociRemoteTests", dependencies: ["LociRemote"], resources: [.copy("Fixtures")], swiftSettings: strict),
    .testTarget(
      name: "LociHostTests", dependencies: ["LociHost", "LociStore", "LociAgents", "LociMedia", "LociRemote"],
      swiftSettings: strict),
    .testTarget(
      name: "LociUITests", dependencies: ["LociUI"], resources: [.copy("Fixtures")], swiftSettings: strict),
    .testTarget(name: "LociToolTests", dependencies: ["LociTool"], swiftSettings: strict),
    .testTarget(name: "ArchitectureTests", swiftSettings: strict),
  ]
)
