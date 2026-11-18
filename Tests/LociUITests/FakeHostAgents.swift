import Foundation
import LociModel

extension FakeHost {
  /// Pi, Claude Code and Codex installed, the rest missing.
  static let installations: [AgentInstallation] = Mentor.Provider.allCases.map { provider in
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

  func agentModels(of provider: Mentor.Provider) async -> [String] {
    switch provider {
    case .claudeCode: ["fable", "opus", "sonnet", "haiku"]
    case .codex: ["gpt-6.1-sol", "gpt-6-luna"]
    default: []
    }
  }

  func agentDefaults() async throws(HostError) -> AgentDefaults {
    AgentDefaults(provider: .claudeCode, models: [.claudeCode: "opus", .codex: "gpt-6.1-sol"])
  }

  func setDefaultAgent(_ command: SetDefaultAgent) async throws(HostError) -> AgentDefaults {
    AgentDefaults(provider: command.provider)
  }

  func setDefaultModel(_ command: SetDefaultModel) async throws(HostError) -> AgentDefaults {
    try await agentDefaults()
  }

  func setMentorAgent(_ command: SetMentorAgent) async throws(HostError) -> Mentor { sample.scheduling }
  func lessonLanguage() async throws(HostError) -> LessonLanguage { .fixed("zh-Hans") }
  func setLessonLanguage(_ command: SetLessonLanguage) async throws(HostError) -> LessonLanguage { command.language }
  func dataLocation() async -> HostPath { HostPath(URL(filePath: "/Users/someone/Loci Dev")) }
}
