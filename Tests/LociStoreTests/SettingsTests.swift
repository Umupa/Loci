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
        settings.defaultRuntimes[.item] = Runtime(provider: .codex, model: "gpt-5", effort: .high)
        settings.speechModel = .recommended
      }

      let read = try store.settings()
      #expect(read.defaultRuntimes == [.item: Runtime(provider: .codex, model: "gpt-5", effort: .high)])
      #expect(read.speechModel == .recommended)
    }
  }

  /// Settings an earlier version wrote, for mentors, are left unchosen; the rest still reads.
  @Test func choicesForMentorsAreForgottenAndTheRestKept() throws {
    try withStore { store in
      try store.writeFile(
        "settings.json", #"{"agent":"grok","models":{"grok":"grok-4"},"lessonLanguage":"en","browserLogin":"chrome"}"#)

      let read = try store.settings()
      #expect(read.defaultRuntimes.isEmpty)
      #expect(read.browserLogin == .chrome)
    }
  }

  @Test func aRuntimeThatCannotBeReadIsLeftUnchosen() throws {
    try withStore { store in
      try store.writeFile("settings.json", #"{"runtime":{"provider":"nobody"}}"#)

      #expect(try store.settings().defaultRuntimes.isEmpty)
    }
  }

  @Test func theOneRuntimeOfEarlierVersionsIsEveryKindsDefault() throws {
    try withStore { store in
      try store.writeFile("settings.json", #"{"runtime":{"provider":"codex","model":"gpt-5"}}"#)

      let old = Runtime(provider: .codex, model: "gpt-5")
      #expect(try store.settings().defaultRuntimes == [.main: old, .item: old, .course: old, .project: old])
      try store.changeSettings { $0.defaultRuntimes[.item] = Runtime(provider: .antigravity) }
      #expect(try !store.readFile("settings.json").contains(#""runtime""#))
      #expect(try store.settings().defaultRuntimes[.project] == old)
    }
  }

  /// L-S26: what each kind last chose up to 1.8.7 is its default, and the file says it came from then until it
  /// is written again.
  @Test func whatEachKindLastChoseBeforeIsItsDefault() throws {
    try withStore { store in
      try store.writeFile("settings.json", #"{"latestRuntimes":{"item":{"provider":"codex","model":"gpt-5"}}}"#)

      let read = try store.settings()
      #expect(read.defaultRuntimes == [.item: Runtime(provider: .codex, model: "gpt-5")])
      #expect(read.keptEveryRuntime)
      try store.changeSettings { _ in }
      #expect(try !store.settings().keptEveryRuntime)
      #expect(try store.settings().defaultRuntimes == [.item: Runtime(provider: .codex, model: "gpt-5")])
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

      try store.changeSettings { $0.defaultRuntimes[.main] = Runtime(provider: .pi) }

      #expect(try store.settings().defaultRuntimes[.main] == Runtime(provider: .pi))
    }
  }
}
