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
        settings.latestRuntimes[.item] = Runtime(provider: .codex, model: "gpt-5", effort: .high)
        settings.speechModel = .recommended
      }

      let read = try store.settings()
      #expect(read.latestRuntimes == [.item: Runtime(provider: .codex, model: "gpt-5", effort: .high)])
      #expect(read.speechModel == .recommended)
    }
  }

  /// Settings an earlier version wrote, for mentors, are left unchosen; the rest still reads.
  @Test func choicesForMentorsAreForgottenAndTheRestKept() throws {
    try withStore { store in
      try store.writeFile(
        "settings.json", #"{"agent":"grok","models":{"grok":"grok-4"},"lessonLanguage":"en","browserLogin":"chrome"}"#)

      let read = try store.settings()
      #expect(read.latestRuntimes.isEmpty)
      #expect(read.browserLogin == .chrome)
    }
  }

  @Test func aRuntimeThatCannotBeReadIsLeftUnchosen() throws {
    try withStore { store in
      try store.writeFile("settings.json", #"{"runtime":{"provider":"nobody"}}"#)

      #expect(try store.settings().latestRuntimes.isEmpty)
    }
  }

  @Test func theOneRuntimeOfEarlierVersionsIsWhatEveryKindOfConversationLastChose() throws {
    try withStore { store in
      try store.writeFile("settings.json", #"{"runtime":{"provider":"codex","model":"gpt-5"}}"#)

      let old = Runtime(provider: .codex, model: "gpt-5")
      #expect(try store.settings().latestRuntimes == [.main: old, .item: old, .course: old, .project: old])
      try store.changeSettings { $0.latestRuntimes[.item] = Runtime(provider: .antigravity) }
      #expect(try !store.readFile("settings.json").contains(#""runtime""#))
      #expect(try store.settings().latestRuntimes[.project] == old)
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

      try store.changeSettings { $0.latestRuntimes[.main] = Runtime(provider: .pi) }

      #expect(try store.settings().latestRuntimes[.main] == Runtime(provider: .pi))
    }
  }
}
