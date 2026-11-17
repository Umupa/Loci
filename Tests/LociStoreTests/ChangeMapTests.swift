import Foundation
import LociModel
import Testing

@testable import LociStore

struct ChangeMapTests {
  static let mentor = Fixture.id(1)
  static let item = Fixture.id(2)
  static let mentorFolder = "mentors/diao-du-\(mentor)"
  static let itemFolder = "library/borg-\(item)"

  static func changes(_ paths: [String], files: [String: EntityID] = [mentorFolder: mentor, itemFolder: item])
    -> Set<ContentChange>
  {
    var map = ChangeMap(folders: [:])
    return map.changes(at: paths) { files[$0] }
  }

  @Test func eachKindOfFileNamesWhatChanged() {
    let lesson = LessonRef(mentor: Self.mentor, lesson: Fixture.slug("intro"))
    let expected: [(String, ContentChange)] = [
      ("\(Self.mentorFolder)/mentor.json", .mentor(Self.mentor)),
      (Self.mentorFolder, .mentor(Self.mentor)),
      ("\(Self.mentorFolder)/catalog.yaml", .catalog(Self.mentor)),
      ("\(Self.mentorFolder)/glossary.yaml", .catalog(Self.mentor)),
      ("\(Self.mentorFolder)/lessons/intro.md", .lesson(lesson)),
      ("\(Self.itemFolder)/item.json", .item(Self.item)),
      ("\(Self.itemFolder)/content.md", .item(Self.item)),
      (Self.itemFolder, .item(Self.item)),
      ("notes/library/\(Self.item).jsonl", .notes(.item(Self.item))),
      ("notes/mentors/\(Self.mentor)/intro.jsonl", .notes(.lesson(lesson))),
    ]
    for (path, change) in expected {
      #expect(Self.changes([path]) == [change], "\(path)")
    }
  }

  @Test func filesTheStoreDoesNotReadAreIgnored() {
    #expect(
      Self.changes([
        "\(Self.mentorFolder)/SOUL.md", "\(Self.mentorFolder)/workspace/notes.txt",
        "\(Self.mentorFolder)/lessons/Intro.md",
        "\(Self.mentorFolder)/.DS_Store", "\(Self.itemFolder)/media.mp4", "notes/library/x.jsonl", "loci.sqlite",
        "mentors",
      ]).isEmpty)
  }

  @Test func theIDInsideTheFolderWinsOverItsName() {
    let other = Fixture.id(7)

    #expect(Self.changes(["\(Self.mentorFolder)/mentor.json"], files: [Self.mentorFolder: other]) == [.mentor(other)])
  }

  @Test func aFolderThatIsGoneIsNamedFromMemoryOrItsName() {
    var map = ChangeMap(folders: ["mentors/renamed": Self.mentor])

    #expect(map.changes(at: ["mentors/renamed"]) { _ in nil } == [.mentor(Self.mentor)])
    #expect(map.changes(at: [Self.itemFolder]) { _ in nil } == [.item(Self.item)])
  }

  @Test func aFolderThatCannotBeIdentifiedAsksForEverything() {
    #expect(Self.changes(["mentors/mystery/catalog.yaml"]) == [.everything])
  }

  @Test func aBatchBecomesOneSet() {
    #expect(
      Self.changes(["\(Self.mentorFolder)/mentor.json", "\(Self.mentorFolder)", "\(Self.itemFolder)/item.json"]) == [
        .mentor(Self.mentor), .item(Self.item),
      ])
  }
}
