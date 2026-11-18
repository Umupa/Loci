import Foundation
import LociModel
import Testing

@testable import LociStore

struct NotesTests {
  static let item = Fixture.id(2)
  static let locator = Locator("loci://library/\(item)#quote=过滤")!

  static func note(_ seed: UInt64, thought: String? = nil, locator: Locator = locator) throws -> Note {
    try Note(id: Fixture.id(seed), locator: locator, thought: thought, savedAt: Fixture.instant)
  }

  @Test func appendedEntriesReadBackAsTheCurrentNotes() throws {
    try withStore { store in
      try store.append(.saved(try Self.note(10)), on: .item(Self.item))
      try store.append(.saved(try Self.note(11)), on: .item(Self.item))
      try store.append(.saved(try Self.note(10, thought: "像漏斗")), on: .item(Self.item))
      try store.append(.deleted(Fixture.id(11), at: Fixture.instant), on: .item(Self.item))

      #expect(store.notes(on: .item(Self.item)) == Loaded(value: [try Self.note(10, thought: "像漏斗")], problems: []))
    }
  }

  @Test func eachEntryIsOneSortedLine() throws {
    try withStore { store in
      try store.append(.saved(try Self.note(10, thought: "像漏斗")), on: .item(Self.item))
      try store.append(.deleted(Fixture.id(10), at: Fixture.instant), on: .item(Self.item))

      #expect(
        try store.readFile("notes/library/\(Self.item).jsonl") == """
          {"event":"saved","id":"\(Fixture.id(10))","locator":"\(Self.locator)","savedAt":"2025-11-17T00:00:00.123Z","thought":"像漏斗"}
          {"at":"2025-11-17T00:00:00.123Z","event":"deleted","id":"\(Fixture.id(10))"}

          """)
    }
  }

  @Test func contentWithoutNotesHasNone() throws {
    try withStore { store in
      #expect(store.notes(on: .item(Self.item)) == Loaded(value: [], problems: []))
    }
  }

  @Test func aNoteForOtherContentIsRefused() throws {
    try withStore { store in
      #expect(throws: StoreError.misplacedNote(Fixture.id(10))) {
        try store.append(.saved(try Self.note(10)), on: .item(Fixture.id(3)))
      }
    }
  }

  @Test func badLinesAreSkippedAndReportedWhileTheRestCount() throws {
    try withStore { store in
      let path = "notes/library/\(Self.item).jsonl"
      let elsewhere = try Self.note(12, locator: Locator("loci://library/\(Fixture.id(3))#quote=x")!)
      try store.append(.saved(try Self.note(10)), on: .item(Self.item))
      try store.writeFile(
        path,
        try store.readFile(path) + "{not json}\n"
          + String(decoding: try Formats.line(NoteEntry.saved(elsewhere)), as: UTF8.self))
      try store.append(.saved(try Self.note(11)), on: .item(Self.item))

      let notes = store.notes(on: .item(Self.item))

      #expect(notes.value == [try Self.note(10), try Self.note(11)])
      #expect(notes.problems.map(\.kind) == [.invalid, .misplacedNote])
      #expect(notes.problems.map(\.path) == [path, path])
      #expect(notes.problems[0].reason.hasPrefix("line 2:"))
    }
  }

  @Test func aLineCutShortByACrashDoesNotSwallowTheNextOne() throws {
    try withStore { store in
      let path = "notes/library/\(Self.item).jsonl"
      try store.append(.saved(try Self.note(10)), on: .item(Self.item))
      try store.writeFile(path, try store.readFile(path) + #"{"event":"saved","id":"#)
      try store.append(.saved(try Self.note(11)), on: .item(Self.item))

      let notes = store.notes(on: .item(Self.item))

      #expect(notes.value == [try Self.note(10), try Self.note(11)])
      #expect(notes.problems.count == 1)
    }
  }
}
