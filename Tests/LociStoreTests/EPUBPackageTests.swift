import Foundation
import LociModel
import Testing

@testable import LociStore

struct EPUBPackageTests {
  static func read(_ data: Data) throws(BookProblem) -> BookImport {
    let file: URL
    do {
      file = try BookFixture.write(data, named: "book.epub")
    } catch {
      throw .damaged
    }
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    return try Store.readBook(file)
  }

  static func package(_ data: Data) throws -> EPUBPackage {
    try EPUBPackage(try BookArchive(data: data))
  }

  @Test func titleAuthorsAndLanguageComeFromThePackage() throws {
    let book = try Self.read(BookFixture.epub(creators: ["魯迅", "Lu Xun"]))

    #expect(book.title == "吶喊")
    #expect(book.authors == ["魯迅", "Lu Xun"])
    #expect(book.language == "zh-Hant")
    #expect(book.format == .epub)
  }

  @Test func aBookWithoutATitleIsCalledAfterItsFile() throws {
    #expect(try Self.read(BookFixture.epub(title: nil)).title == "book")
  }

  @Test func chaptersFollowTheSpineWithTheirUnpackedLength() throws {
    let package = try Self.package(BookFixture.epub())

    #expect(package.chapters.map(\.path) == ["OPS/c1.xhtml", "OPS/c2.xhtml", "OPS/c3.xhtml"])
    #expect(package.chapters.allSatisfy { $0.length > 100 })
  }

  @Test func theTableOfContentsComesFromTheNavigationDocumentWithItsLevels() throws {
    let toc = try Self.package(BookFixture.epub()).toc

    #expect(
      toc == [
        .init(title: "自序", depth: 0, chapter: 0),
        .init(title: "狂人日記", depth: 1, chapter: 1, anchor: "s1"),
        .init(title: "孔乙己", depth: 1, chapter: 2),
      ])
  }

  @Test func anEPUB2BookTakesItsTableOfContentsFromTheNCX() throws {
    let toc = try Self.package(BookFixture.epub(navigation: false, ncx: true)).toc

    #expect(toc == [.init(title: "One", depth: 0, chapter: 0), .init(title: "Two", depth: 1, chapter: 1, anchor: "x")])
  }

  @Test func aBookWithNoTableOfContentsGetsOneLinePerChapter() throws {
    #expect(try Self.package(BookFixture.epub(navigation: false)).toc.map(\.title) == ["1", "2", "3"])
  }

  @Test func theCoverIsTheCoverImageOrTheOneTheMetadataNames() throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let three = try Self.read(
      BookFixture.epub(
        manifest: #"<item id="cv" href="images/front.png" media-type="image/png" properties="cover-image"/>"#,
        extra: [("OPS/images/front.png", png)]))
    let two = try Self.read(
      BookFixture.epub(
        meta: #"<meta name="cover" content="pic"/>"#,
        manifest: #"<item id="pic" href="cover.jpg" media-type="image/jpeg"/>"#, extra: [("OPS/cover.jpg", png)]))

    #expect(three.cover?.data == png)
    #expect(three.cover?.pathExtension == "png")
    #expect(two.cover?.pathExtension == "jpg")
    #expect(try Self.read(BookFixture.epub()).cover == nil)
  }

  @Test func aFixedLayoutBookIsNotTakenIn() {
    #expect(throws: BookProblem.fixedLayout) {
      try Self.read(BookFixture.epub(meta: #"<meta property="rendition:layout">pre-paginated</meta>"#))
    }
    let apple = Data(
      #"<display_options><platform name="*"><option name="fixed-layout">true</option></platform></display_options>"#
        .utf8)
    #expect(throws: BookProblem.fixedLayout) {
      try Self.read(BookFixture.epub(extra: [("META-INF/com.apple.ibooks.display-options.xml", apple)]))
    }
  }

  static func encryption(_ algorithm: String) -> Data {
    Data(
      """
      <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
      <enc:EncryptedData><enc:EncryptionMethod Algorithm="\(algorithm)"/></enc:EncryptedData></encryption>
      """.utf8)
  }

  @Test func aBookLockedWithDRMIsNotTakenInButHiddenFontsAreFine() throws {
    #expect(throws: BookProblem.protected) {
      try Self.read(
        BookFixture.epub(extra: [
          ("META-INF/encryption.xml", Self.encryption("http://www.w3.org/2001/04/xmlenc#aes128-cbc"))
        ]))
    }
    #expect(throws: BookProblem.protected) {
      try Self.read(BookFixture.epub(extra: [("META-INF/rights.xml", Data("<rights/>".utf8))]))
    }
    let fonts = try Self.read(
      BookFixture.epub(extra: [("META-INF/encryption.xml", Self.encryption("http://www.idpf.org/2008/embedding"))]))
    #expect(fonts.title == "吶喊")
  }

  @Test func aBrokenArchiveOrPackageIsDamaged() {
    #expect(throws: BookProblem.damaged) { try Self.read(Data("PK not really".utf8)) }
    #expect(throws: BookProblem.damaged) { try Self.read(BookFixture.epub(container: false)) }
    #expect(throws: BookProblem.notABook) {
      try Self.read(BookFixture.archive([(name: "a.txt", data: Data("x".utf8), deflated: false)]))
    }
  }

  @Test(arguments: [
    ("c2.xhtml#s1", "OPS", "OPS/c2.xhtml", "s1"), ("../a%20b.xhtml", "OPS/text", "OPS/a b.xhtml", nil),
    ("./x.css", "", "x.css", nil),
  ])
  func linksResolveFromTheFolderOfTheFileTheyAreIn(href: String, folder: String, path: String, anchor: String?) {
    let resolved = EPUBPackage.resolve(href, from: folder)

    #expect(resolved.path == path)
    #expect(resolved.anchor == anchor)
  }
}
