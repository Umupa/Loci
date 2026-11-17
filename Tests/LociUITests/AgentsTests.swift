import Foundation
import LociModel
import Testing

@testable import LociUI

struct AgentsTests {
  /// α2-S10: Pi and Grok can be chosen even when the probe has not found them.
  @Test func piAndGrokCanAlwaysBeChosen() {
    #expect(Agents.choosable([], keeping: .pi) == [.pi, .grok])
  }

  @Test func everyInstalledAgentCanBeChosen() {
    #expect(Agents.choosable(FakeHost.installations, keeping: .pi) == [.pi, .grok, .claudeCode, .codex])
  }

  @Test func theAgentInUseStaysChoosableAfterItIsUninstalled() {
    #expect(Agents.choosable([.missing(.codex)], keeping: .codex) == [.pi, .grok, .codex])
  }
}
