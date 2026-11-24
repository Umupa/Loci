import Foundation
import LociModel
import Testing

@testable import LociStore

struct BookFilesTests {
  static func book(_ seed: UInt64 = 7, title: String = "吶喊") throws -> Item {
    try Item(id: Fixture.id(seed), kind: .book, title: title, authors: ["魯迅"])
  }

  @Test func aBookIsKeptAsItCameWithItsCoverAndReadFromTheArchive() throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let file = try BookFixture.write(
      BookFixture.epub(
        manifest: #"<item id="cv" href="c.png" media-type="image/png" properties="cover-image"/>"#,
        extra: [("OPS/c.png", png)]), named: "nahan.epub")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try withStore { store in
      let item = try Self.book()
      try store.addBook(item, copying: file, as: try Store.readBook(file))
      let folder = try store.itemFolder(item.id)

      #expect(try Data(contentsOf: folder.appending(path: "book.epub")) == Data(contentsOf: file))
      #expect(try store.cover(of: item.id) == png)
      #expect(try store.item(item.id) == item)
      #expect(try store.bookContents(of: item.id).chapters.count == 3)
      #expect(String(decoding: try store.bookFile("OPS/c3.xhtml", of: item.id), as: UTF8.self).contains("魯鎮"))
      #expect(throws: StoreError.notFound("OPS/none.xhtml")) { try store.bookFile("OPS/none.xhtml", of: item.id) }
      #expect(try store.itemFiles(item.id).content == nil)
    }
  }

  @Test func aTextBookIsKeptAsItsBytesAndServedAsChapterPages() throws {
    let file = try BookFixture.write(TextBookTests.gb18030("第一章 開始\n　　正文。\n第二章 後來\n　　結尾。"), named: "小說.txt")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    try withStore { store in
      let read = try Store.readBook(file)
      let item = try Self.book(title: read.title)
      try store.addBook(item, copying: file, as: read)

      #expect(read.title == "小說")
      #expect(try store.bookContents(of: item.id).toc.map(\.title) == ["第一章 開始", "第二章 後來"])
      #expect(String(decoding: try store.bookFile("chapter-1.xhtml", of: item.id), as: UTF8.self).contains("結尾。"))
      #expect(throws: StoreError.notFound("chapter-2.xhtml")) { try store.bookFile("chapter-2.xhtml", of: item.id) }
    }
  }

  @Test func nothingIsLeftBehindWhenTheBookCannotBeCopied() throws {
    try withStore { store in
      let item = try Self.book()
      let missing = FileManager.default.temporaryDirectory.appending(path: "gone-\(UUID().uuidString).epub")
      let read = BookImport(title: "x", authors: [], language: nil, cover: nil, format: .epub)

      #expect(throws: (any Error).self) { try store.addBook(item, copying: missing, as: read) }
      #expect(throws: (any Error).self) { try store.itemFolder(item.id) }
      #expect(store.subfolders(of: store.libraryFolder).isEmpty)
    }
  }

  @Test func onlyEPUBAndTextFilesCanBeBooks() throws {
    let file = try BookFixture.write(Data("# x".utf8), named: "a.md")
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    #expect(throws: BookProblem.notABook) { try Store.readBook(file) }
  }
}
