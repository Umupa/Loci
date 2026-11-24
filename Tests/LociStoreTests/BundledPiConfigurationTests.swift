import Foundation
import LociModel
import Testing

@testable import LociStore

struct BundledPiConfigurationTests {
  @Test func eachOwnAddressGetsItsOwnConfigurationWithoutAKeyOnDiskOrInBash() throws {
    try withSupport { support in
      let first = try service(custom: "https://first.example.test/v1")
      let second = try service(custom: "https://second.example.test/v1")
      let configuration = try support.preparePiConfiguration(for: first)
      #expect(try support.preparePiConfiguration(for: second).directory != configuration.directory)
      #expect(configuration.model == "loci-model/test-model")
      #expect(configuration.keyVariable == "LOCI_MODEL_API_KEY")
      let text = try String(contentsOf: configuration.directory.appending(path: "models.json"), encoding: .utf8)
      #expect(text.contains("${LOCI_MODEL_API_KEY}"))
      #expect(text.contains("first.example.test"))
      #expect(text.contains("openai-completions"))
      #expect(!text.contains("second.example.test"))

      let shell = Process()
      shell.executableURL = configuration.directory.appending(path: "loci-shell")
      shell.arguments = [
        "-c", "test -z \"$LOCI_MODEL_API_KEY$OPENAI_API_KEY$ANTHROPIC_API_KEY$OPENROUTER_API_KEY$DEEPSEEK_API_KEY\"",
      ]
      shell.environment = [
        "PATH": "/usr/bin:/bin", "LOCI_MODEL_API_KEY": "fixture-value", "OPENAI_API_KEY": "fixture-value",
        "ANTHROPIC_API_KEY": "fixture-value", "OPENROUTER_API_KEY": "fixture-value",
        "DEEPSEEK_API_KEY": "fixture-value",
      ]
      try shell.run()
      shell.waitUntilExit()
      #expect(shell.terminationStatus == 0)
    }
  }

  @Test func aPresetPiKnowsUsesPisOwnProviderAndTheRestAreLocis() throws {
    try withSupport { support in
      let deepSeek = try support.preparePiConfiguration(for: try service(.deepSeek))
      #expect(deepSeek.model == "deepseek/test-model")
      #expect(deepSeek.keyVariable == "DEEPSEEK_API_KEY")
      #expect(!FileManager.default.fileExists(atPath: deepSeek.directory.appending(path: "models.json").path()))

      let kimi = try support.preparePiConfiguration(for: try service(.kimi))
      #expect(kimi.model == "loci-model/test-model")
      let text = try String(contentsOf: kimi.directory.appending(path: "models.json"), encoding: .utf8)
      #expect(text.contains("api.moonshot.cn"))
    }
  }

  @Test func anAnthropicAddressOfYourOwnIsGivenToPiWithoutItsVersion() throws {
    try withSupport { support in
      var provider = ModelProvider(custom: EntityID(), api: .anthropic)
      provider.address = ModelAddress("https://api.minimax.cn/anthropic/v1")
      let address = try #require(provider.address)
      let configuration = try support.preparePiConfiguration(
        for: ModelService(on: provider, at: address, model: "MiniMax-M3"))
      let text = try String(contentsOf: configuration.directory.appending(path: "models.json"), encoding: .utf8)
      #expect(text.contains("anthropic-messages"))
      #expect(text.contains(#""baseUrl" : "https://api.minimax.cn/anthropic/""#))
      #expect(text.contains(#""authHeader" : false"#))
    }
  }

  private func withSupport(_ body: (Support) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(Support(root: root))
  }

  private func service(_ preset: ModelPreset) throws -> ModelService {
    let provider = ModelProvider(preset)
    return ModelService(on: provider, at: try #require(provider.address), model: "test-model")
  }

  private func service(custom address: String) throws -> ModelService {
    var provider = ModelProvider(custom: EntityID(), api: .openAI)
    provider.address = ModelAddress(address)
    return ModelService(on: provider, at: try #require(provider.address), model: "test-model")
  }
}
