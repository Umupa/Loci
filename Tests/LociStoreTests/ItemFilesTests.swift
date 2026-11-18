import Foundation
import LociModel
import Testing

@testable import LociStore

struct ItemFilesTests {
  @Test func anArticlesTextIsItsMarkdown() throws {
    try withStore { store in
      let item = try Fixture.item()
      try store.add(item, content: "text")

      let files = try store.itemFiles(item.id)
      #expect(files.content?.lastPathComponent == "content.md")
      #expect(files.content?.deletingLastPathComponent() == files.folder)
      #expect(files.notes.path(percentEncoded: false).hasSuffix("notes/library/\(item.id).jsonl"))
    }
  }

  @Test func aPaperIsReadFromItsPDFAndAVideoFromItsTranscript() throws {
    try withStore { store in
      let paper = try Item(id: Fixture.id(7), kind: .paper, title: "Raft")
      try store.add(paper, content: "")
      let folder = try store.itemFiles(paper.id).folder
      try FileManager.default.removeItem(at: folder.appending(path: "content.md"))
      try Data("%PDF-".utf8).write(to: folder.appending(path: "content.pdf"))
      #expect(try store.itemFiles(paper.id).content?.lastPathComponent == "content.pdf")

      try FileManager.default.removeItem(at: folder.appending(path: "content.pdf"))
      #expect(try store.itemFiles(paper.id).content == nil)
      try Data("{}".utf8).write(to: folder.appending(path: "transcript.json"))
      #expect(try store.itemFiles(paper.id).content?.lastPathComponent == "transcript.json")
    }
  }
}
