import Foundation
import Testing

@testable import LociStore

struct BookArchiveTests {
  @Test func readsFilesStoredAsTheyAreAndDeflated() throws {
    let text = Data(String(repeating: "孔乙己是站着喝酒而穿長衫的唯一的人。", count: 50).utf8)
    let archive = try BookArchive(
      data: BookFixture.archive([
        (name: "mimetype", data: Data("application/epub+zip".utf8), deflated: false),
        (name: "OPS/a.xhtml", data: text, deflated: true),
      ]))

    #expect(try archive.file("mimetype") == Data("application/epub+zip".utf8))
    #expect(try archive.file("OPS/a.xhtml") == text)
    #expect(archive.size(of: "OPS/a.xhtml") == text.count)
  }

  @Test func aMissingFileIsMissing() throws {
    let archive = try BookArchive(data: BookFixture.archive([(name: "a", data: Data("x".utf8), deflated: false)]))

    #expect(throws: BookArchive.Failure.missing("b")) { try archive.file("b") }
  }

  @Test func somethingThatIsNotAnArchiveOrIsCutShortIsRejected() {
    let whole = BookFixture.archive([(name: "a", data: Data("x".utf8), deflated: false)])

    #expect(throws: BookArchive.Failure.notAnArchive) { try BookArchive(data: Data("not a zip".utf8)) }
    #expect(throws: BookArchive.Failure.notAnArchive) { try BookArchive(data: whole.prefix(whole.count - 10)) }
  }

  @Test func aFileWhoseBytesAreBrokenIsDamaged() throws {
    var data = BookFixture.archive([(name: "a", data: Data(repeating: 65, count: 400), deflated: true)])
    data.replaceSubrange(31..<33, with: Data([0xFF, 0xFF]))
    let archive = try BookArchive(data: data)

    #expect(throws: BookArchive.Failure.self) { try archive.file("a") }
  }
}
