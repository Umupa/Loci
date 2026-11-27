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

    #expect(
      await list.models(of: .pi) == [
        AgentModel(id: "anthropic/claude-opus-5-5", name: "claude-opus-5-5"),
        AgentModel(id: "openai/gpt-6.1-sol", name: "gpt-6.1-sol"),
      ])
  }

  @Test func codexListsTheModelsItShowsInItsPicker() async throws {
    let catalog = """
      {"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list"},
      {"slug":"internal","visibility":"hide"},{"slug":"gpt-6-luna","visibility":"list"}]}
      """
    let (list, folder) = try list("codex", ["codex debug models": .init(output: catalog)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(
      await list.models(of: .codex) == [
        AgentModel(id: "gpt-6.1-sol", name: "GPT-6.1-Sol"), AgentModel(id: "gpt-6-luna", name: "gpt-6-luna"),
      ])
  }

  /// A model agy lists once for each of several efforts is one model; one it lists once keeps its own name.
  @Test func antigravityListsEachModelOnceWithTheEffortChosenApart() async throws {
    let rows = """
      gemini-4-hydrogen-high\tGemini 4 Hydrogen (High)
      gemini-4-hydrogen-xhigh\tGemini 4 Hydrogen (XHigh)
      gemini-4-hydrogen-low\tGemini 4 Hydrogen (Low)
      claude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)
      gpt-oss-120b-medium\tGPT-OSS 120B (Medium)

      """
    let (list, folder) = try list("agy", ["agy models": .init(output: rows)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(
      await list.models(of: .antigravity) == [
        AgentModel(id: "gemini-4-hydrogen", name: "Gemini 4 Hydrogen"),
        AgentModel(id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6 (Thinking)"),
        AgentModel(id: "gpt-oss-120b-medium", name: "GPT-OSS 120B (Medium)"),
      ])
  }

  @Test func claudeCodeOffersTheAliasesItDocuments() async throws {
    let (list, folder) = try list("claude", [:])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .claudeCode).map(\.name) == ["Fable", "Opus", "Sonnet", "Haiku"])
  }

  @Test func anAgentThatIsMissingOrCannotListHasNoModels() async throws {
    let (list, folder) = try list("pi", ["pi --list-models": .init(output: "", status: 1)])
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(await list.models(of: .pi).isEmpty)
    #expect(await list.models(of: .codex).isEmpty)
    #expect(await list.models(of: .grok).isEmpty)
  }
}
