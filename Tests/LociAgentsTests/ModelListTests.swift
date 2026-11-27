import Foundation
import LociModel
import Testing

@testable import LociAgents

struct ModelListTests {
  private func list(_ program: String, _ answers: [String: ProbeLauncher.Answer]) throws -> (ModelList, URL) {
    let folder = try probeFolder()
    try probeProgram(program, in: folder)
    let list = ModelList(
      launcher: ProbeLauncher(answers), search: AgentSearch(directories: [folder]), workingDirectory: folder)
    return (list, folder)
  }

  @Test func piListsEveryModelWithItsProvider() async throws {
    let table = """
      provider      model              context  max-out  thinking  images
      anthropic     claude-opus-5-5    1M       128K     yes       yes
      openai        gpt-6.1-sol        500K     128K     yes       yes

      """
    let (list, folder) = try list("pi", ["pi --list-models": .init(output: table)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .pi) == ["anthropic/claude-opus-5-5", "openai/gpt-6.1-sol"])
  }

  @Test func codexListsTheModelsItShowsInItsPicker() async throws {
    let catalog = """
      {"models":[{"slug":"gpt-6.1-sol","visibility":"list"},{"slug":"internal","visibility":"hide"},
      {"slug":"gpt-6-luna","visibility":"list"}]}
      """
    let (list, folder) = try list("codex", ["codex debug models": .init(output: catalog)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .codex) == ["gpt-6.1-sol", "gpt-6-luna"])
  }

  @Test func antigravityListsTheModelIDsAgyPrints() async throws {
    let rows = """
      gemini-4-hydrogen-high\tGemini 4 Hydrogen (High)
      claude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)

      """
    let (list, folder) = try list("agy", ["agy models": .init(output: rows)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .antigravity) == ["gemini-4-hydrogen-high", "claude-sonnet-4-6"])
  }

  @Test func claudeCodeOffersTheAliasesItDocuments() async throws {
    let (list, folder) = try list("claude", [:])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .claudeCode) == ["fable", "opus", "sonnet", "haiku"])
  }

  @Test func anAgentThatIsMissingOrCannotListHasNoModels() async throws {
    let (list, folder) = try list("pi", ["pi --list-models": .init(output: "", status: 1)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .pi).isEmpty)
    #expect(await list.models(of: .codex).isEmpty)
    #expect(await list.models(of: .grok).isEmpty)
  }
}
