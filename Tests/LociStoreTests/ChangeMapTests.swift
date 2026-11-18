import Foundation
import LociModel
import Testing

@testable import LociStore

struct ChangeMapTests {
  static let item = Fixture.id(2)
  static let itemFolder = "library/borg-\(item)"

  static func changes(_ paths: [String], files: [String: EntityID] = [itemFolder: item]) -> Set<ContentChange> {
    var map = ChangeMap(folders: [:])
    return map.changes(at: paths) { files[$0] }
  }

  @Test func eachKindOfFileNamesWhatChanged() {
    let expected: [(String, ContentChange)] = [
      ("\(Self.itemFolder)/item.json", .item(Self.item)),
      ("\(Self.itemFolder)/content.md", .item(Self.item)),
      (Self.itemFolder, .item(Self.item)),
      ("notes/library/\(Self.item).jsonl", .notes(.item(Self.item))),
      ("agent/SOUL.md", .loci(.soul)),
      ("agent/USER.md", .loci(.profile)),
      ("agent/MEMORY.md", .loci(.memory)),
      ("agent/notes/2026-11-18.md", .loci(.notes)),
      ("agent/notes", .loci(.notes)),
      ("agent/diary/2026-11-17.md", .loci(.diary)),
      ("agent/avatar.png", .loci(.avatar)),
    ]
    for (path, change) in expected {
      #expect(Self.changes([path]) == [change], "\(path)")
    }
  }

  @Test func filesTheStoreDoesNotReadAreIgnored() {
    #expect(
      Self.changes([
        "agent/AGENTS.md", "agent/CLAUDE.md", "agent/workspace/clone/README.md",
        "agent/conversations/2026-11-18/main-x.md", "agent/.DS_Store", "agent/SOUL.md.swp",
        "\(Self.itemFolder)/.work/media.mp4.part", "notes/library/x.jsonl", "loci.sqlite", "mentors/old/mentor.json",
        "agent",
      ]).isEmpty)
  }

  @Test func theIDInsideTheFolderWinsOverItsName() {
    let other = Fixture.id(7)

    #expect(Self.changes(["\(Self.itemFolder)/item.json"], files: [Self.itemFolder: other]) == [.item(other)])
  }

  @Test func aFolderThatIsGoneIsNamedFromMemoryOrItsName() {
    var map = ChangeMap(folders: ["library/renamed": Self.item])

    #expect(map.changes(at: ["library/renamed"]) { _ in nil } == [.item(Self.item)])
    #expect(map.changes(at: [Self.itemFolder]) { _ in nil } == [.item(Self.item)])
  }

  @Test func aFolderThatCannotBeIdentifiedAsksForEverything() {
    #expect(Self.changes(["library/mystery/item.json"]) == [.everything])
  }

  @Test func aBatchBecomesOneSet() {
    #expect(
      Self.changes(["agent/SOUL.md", "agent/MEMORY.md", "\(Self.itemFolder)/item.json", Self.itemFolder]) == [
        .loci(.soul), .loci(.memory), .item(Self.item),
      ])
  }
}
