import Foundation
import LociModel
import Testing

@testable import LociStore

struct SettingsTests {
  @Test func aFolderWithoutSettingsHasNoChoices() throws {
    try withStore { store in
      let settings = try store.settings()

      #expect(settings == HostSettings())
    }
  }

  @Test func settingsReadBackAfterSaving() throws {
    try withStore { store in
      try store.changeSettings { settings in
        settings.agent = .grok
        settings.models = [.grok: "grok-4", .pi: "deepseek"]
        settings.lessonLanguage = .fixed("zh-Hans")
      }

      let read = try store.settings()
      #expect(read.agent == .grok)
      #expect(read.models == [.grok: "grok-4", .pi: "deepseek"])
      #expect(read.lessonLanguage == .fixed("zh-Hans"))
    }
  }

  /// Settings written before each agent had its own model keep the agent and its model.
  @Test func theEarlierChoiceForNewMentorsStillReads() throws {
    try withStore { store in
      try store.writeFile("settings.json", #"{"newMentors":{"provider":"grok","model":"grok-4"}}"#)

      let read = try store.settings()
      #expect(read.agent == .grok)
      #expect(read.models == [.grok: "grok-4"])
    }
  }

  @Test func aSettingsFileThatCannotBeReadIsReported() throws {
    try withStore { store in
      try store.writeFile("settings.json", "{ not json")

      #expect(throws: StoreError.self) { try store.settings() }
    }
  }

  @Test func savingReplacesASettingsFileThatCannotBeRead() throws {
    try withStore { store in
      try store.writeFile("settings.json", "{ not json")

      try store.changeSettings { $0.agent = .pi }

      #expect(try store.settings().agent == .pi)
    }
  }
}
