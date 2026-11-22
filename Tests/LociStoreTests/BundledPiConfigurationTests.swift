import Foundation
import LociModel
import Testing

@testable import LociStore

struct BundledPiConfigurationTests {
  @Test func eachCompatibleEndpointGetsItsOwnConfigurationWithoutAKeyOnDiskOrInBash() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let support = Support(root: root)
    let first = try #require(
      ModelService(
        provider: .compatible, model: "test-model", baseURL: URL(string: "https://first.example.test/v1")))
    let second = try #require(
      ModelService(
        provider: .compatible, model: "test-model", baseURL: URL(string: "https://second.example.test/v1")))
    let directory = try support.preparePiConfiguration(for: first)
    #expect(try support.preparePiConfiguration(for: second) != directory)
    let text = try String(contentsOf: directory.appending(path: "models.json"), encoding: .utf8)
    #expect(text.contains("${LOCI_MODEL_API_KEY}"))
    #expect(text.contains("first.example.test"))
    #expect(!text.contains("second.example.test"))

    let shell = Process()
    shell.executableURL = directory.appending(path: "loci-shell")
    shell.arguments = [
      "-c", "test -z \"$LOCI_MODEL_API_KEY$OPENAI_API_KEY$ANTHROPIC_API_KEY$OPENROUTER_API_KEY$DEEPSEEK_API_KEY\"",
    ]
    shell.environment = [
      "PATH": "/usr/bin:/bin", "LOCI_MODEL_API_KEY": "fixture-value", "OPENAI_API_KEY": "fixture-value",
      "ANTHROPIC_API_KEY": "fixture-value", "OPENROUTER_API_KEY": "fixture-value", "DEEPSEEK_API_KEY": "fixture-value",
    ]
    try shell.run()
    shell.waitUntilExit()
    #expect(shell.terminationStatus == 0)
  }
}
