import Foundation
import LociModel

extension FakeHost {
  /// Pi and Claude Code installed, the rest missing.
  static let installations: [AgentInstallation] = Mentor.Provider.allCases.map { provider in
    switch provider {
    case .pi:
      .installed(
        .init(
          provider: .pi, executable: URL(filePath: "/Users/me/.local/bin/pi"), version: "0.62.0", signIn: .unknown))
    case .claudeCode:
      .installed(
        .init(
          provider: .claudeCode, executable: URL(filePath: "/opt/homebrew/bin/claude"),
          version: "2.1.326 (Claude Code)", signIn: .signedIn))
    default:
      .missing(provider)
    }
  }

  func detectAgents(again: Bool) async -> [AgentInstallation] { Self.installations }
  func newMentorAgent() async throws(HostError) -> AgentChoice { AgentChoice(provider: .pi, model: "deepseek-v4") }
  func setNewMentorAgent(_ command: SetNewMentorAgent) async throws(HostError) -> AgentChoice { command.choice }
  func setMentorAgent(_ command: SetMentorAgent) async throws(HostError) -> Mentor { sample.scheduling }
}
