import Foundation
import LociModel

extension FakeHost {
  /// Pi, Claude Code and Codex installed, the rest missing.
  static let installations: [AgentInstallation] = Provider.allCases.map { provider in
    switch provider {
    case .pi:
      .installed(
        .init(
          provider: .pi, executable: HostPath(URL(filePath: "/Users/me/.local/bin/pi")), version: "0.62.0",
          signIn: .unknown))
    case .claudeCode:
      .installed(
        .init(
          provider: .claudeCode, executable: HostPath(URL(filePath: "/opt/homebrew/bin/claude")),
          version: "2.1.326 (Claude Code)", signIn: .signedIn))
    case .codex:
      .installed(
        .init(
          provider: .codex, executable: HostPath(URL(filePath: "/opt/homebrew/bin/codex")),
          version: "codex-cli 0.167.1",
          signIn: .unknown))
    default:
      .missing(provider)
    }
  }

  func detectAgents(again: Bool) async -> [AgentInstallation] { Self.installations }

  func agentModels(of provider: Provider) async -> [AgentModel] {
    switch provider {
    case .claudeCode: ["fable", "opus", "sonnet", "haiku"].map { AgentModel(id: $0, name: $0.capitalized) }
    case .codex: [AgentModel(id: "gpt-6.1-sol", name: "GPT-6.1-Sol"), AgentModel(id: "gpt-6-luna", name: "GPT-6 Luna")]
    case .antigravity: [AgentModel(id: "gemini-4-hydrogen", name: "Gemini 4 Hydrogen")]
    default: []
    }
  }

  func runtime(of conversation: ConversationRef) async throws(HostError) -> Runtime {
    sample.ownRuntimes.first { $0.conversation == conversation }?.runtime ?? sample.runtime
  }

  func runtimeInUse(of conversation: ConversationRef) async throws(HostError) -> RuntimeInUse {
    let own = sample.ownRuntimes.first { $0.conversation == conversation }?.runtime
    return RuntimeInUse(runtime: own ?? sample.runtime, kindDefault: sample.runtime, isOwn: own != nil)
  }

  func runtimeDefaults() async throws(HostError) -> RuntimeDefaults {
    RuntimeDefaults(
      kinds: ConversationKind.allCases.map { kind in
        .init(
          kind: kind,
          runtime: kind == .item ? Runtime(provider: .claudeCode, model: "opus", effort: .medium) : sample.runtime)
      },
      own: sample.ownRuntimes)
  }

  func setRuntime(_ command: SetConversationRuntime) async throws(HostError) -> Runtime {
    command.runtime ?? sample.runtime
  }

  func setDefaultRuntime(_ command: SetDefaultRuntime) async throws(HostError) -> Runtime { command.runtime }
  func dataLocation() async -> HostPath { HostPath(URL(filePath: "/Users/someone/Loci-Beta")) }
}
