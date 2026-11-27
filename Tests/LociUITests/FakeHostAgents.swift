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

  func agentModels(of provider: Provider) async -> [String] {
    switch provider {
    case .claudeCode: ["fable", "opus", "sonnet", "haiku"]
    case .codex: ["gpt-6.1-sol", "gpt-6-luna"]
    default: []
    }
  }

  func runtime(of conversation: ConversationRef) async throws(HostError) -> Runtime { sample.runtime }
  func setRuntime(_ command: SetConversationRuntime) async throws(HostError) -> Runtime { command.runtime }
  func dataLocation() async -> HostPath { HostPath(URL(filePath: "/Users/someone/Loci-Beta")) }
}
