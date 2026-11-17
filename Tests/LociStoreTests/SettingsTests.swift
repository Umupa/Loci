import Foundation
import LociModel
import Testing

@testable import LociStore

struct SettingsTests {
  @Test func aFolderWithoutSettingsHasNoChosenAgent() throws {
    try withStore { store in
      let chosen = try store.newMentorAgent()

      #expect(chosen == nil)
    }
  }

  @Test func theAgentForNewMentorsReadsBackAfterSaving() throws {
    try withStore { store in
      try store.save(newMentorAgent: AgentChoice(provider: .grok, model: "grok-4"))

      #expect(try store.newMentorAgent() == AgentChoice(provider: .grok, model: "grok-4"))
    }
  }

  @Test func aSettingsFileThatCannotBeReadIsReported() throws {
    try withStore { store in
      try store.writeFile("settings.json", "{ not json")

      #expect(throws: StoreError.self) { try store.newMentorAgent() }
    }
  }

  @Test func savingReplacesASettingsFileThatCannotBeRead() throws {
    try withStore { store in
      try store.writeFile("settings.json", "{ not json")

      try store.save(newMentorAgent: AgentChoice(provider: .pi))

      #expect(try store.newMentorAgent() == AgentChoice(provider: .pi))
    }
  }
}
