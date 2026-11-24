import Foundation
import LociModel
import Testing

@testable import LociHost

/// BK-S1, BK-S3, BK-S4, BK-S8, BK-S11, BK-S13: books taken in, read and remembered through the host.
struct BookScenarioTests {
  static func epub(title: String = "吶喊", layout: String = "") -> Data {
    let opf = """
      <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(title)</dc:title><dc:creator>魯迅</dc:creator>
      <dc:language>zh</dc:language>\(layout)</metadata>
      <manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
      <item id="cv" href="cv.png" media-type="image/png" properties="cover-image"/></manifest>
      <spine><itemref idref="a"/></spine></package>
      """
    return StoredZip.archive([
      ("mimetype", Data("application/epub+zip".utf8)),
      (
        "META-INF/container.xml",
        Data(
          #"<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>"#
            .utf8)
      ),
      ("content.opf", Data(opf.utf8)),
      ("a.xhtml", Data(#"<html xmlns="http://www.w3.org/1999/xhtml"><body><p>今天晚上，很好的月光。</p></body></html>"#.utf8)),
      ("cv.png", Data([0x89, 0x50, 0x4E, 0x47])),
    ])
  }

  static func upload(_ data: Data, named name: String, to host: LocalHost, in place: Place) async throws -> Upload {
    let file = place.root.appending(path: ".outside/\(UUID().uuidString)/\(name)")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file)
    return try await host.upload(LocalFile(file))
  }

  /// BK-S1, BK-S11, BK-S13: the book is in the library with its cover, title and authors, and the companion
  /// sees no more than that.
  @Test func anEPUBComesInWithItsCoverTitleAndAuthors() async throws {
    try await withHost { host, place, _ in
      let item = try await host.run(
        ImportBook(upload: try await Self.upload(Self.epub(), named: "x.epub", to: host, in: place)))

      #expect(item.kind == .book)
      #expect(item.title == "吶喊")
      #expect(item.authors == ["魯迅"])
      #expect(try await host.run(ListItems()).contains(item))
      #expect(try await host.run(ReadCover(item: item.id)) == Data([0x89, 0x50, 0x4E, 0x47]))
      let contents = try await host.run(ReadBookContents(item: item.id))
      #expect(contents.chapters.map(\.path) == ["a.xhtml"])
      let page = try await host.run(ReadBookFile(item: item.id, path: "a.xhtml"))
      #expect(String(decoding: page, as: UTF8.self).contains("月光"))
      await #expect(throws: HostError.self) { try await host.run(ReadItemText(item: item.id)) }
    }
  }

  /// BK-S3: a GB18030 text file comes in as a book cut at its chapter headings.
  @Test func aTextFileComesInAsABookCutIntoChapters() async throws {
    try await withHost { host, place, _ in
      let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
      let text = try #require("第一章 風雪\n　　林沖踏着那瑞雪。\n第二章 生辰綱\n　　楊志。".data(using: gb18030))

      let item = try await host.run(
        ImportBook(upload: try await Self.upload(text, named: "水滸.txt", to: host, in: place)))

      #expect(item.title == "水滸")
      #expect(try await host.run(ReadBookContents(item: item.id)).toc.map(\.title) == ["第一章 風雪", "第二章 生辰綱"])
    }
  }

  /// BK-S4: a book Loci cannot read leaves nothing behind and says why.
  @Test func aBookThatCannotBeReadLeavesNothingAndSaysWhy() async throws {
    try await withHost { host, place, _ in
      let fixed = Self.epub(layout: #"<meta property="rendition:layout">pre-paginated</meta>"#)
      let cases: [(Data, String, BookProblem)] = [
        (fixed, "comic.epub", .fixedLayout), (Data("PK broken".utf8), "broken.epub", .damaged),
      ]
      for (data, name, problem) in cases {
        let upload = try await Self.upload(data, named: name, to: host, in: place)

        await #expect(throws: HostError.unsupportedBook(problem)) { try await host.run(ImportBook(upload: upload)) }
      }
      #expect(try await host.run(ListItems()).isEmpty)
    }
  }

  /// BK-S8: where the reader is in a book is kept by chapter and character, with how far into the book it is.
  @Test func whereTheReaderIsInABookIsKept() async throws {
    try await withHost { host, place, _ in
      let item = try await host.run(
        ImportBook(upload: try await Self.upload(Self.epub(), named: "x.epub", to: host, in: place)))
      let spot = Locator.item(
        item.id, .spot(try BookSpot(chapter: 0, node: [0, 0], character: 4, share: Fraction(0.3))))

      _ = try await host.run(SaveReadingPosition(content: .item(item.id), position: spot))

      #expect(try await host.run(ReadReadingState(content: .item(item.id)))?.position == spot)
    }
  }
}

/// A ZIP archive of files stored as they are, which is all a test book needs.
enum StoredZip {
  static func archive(_ files: [(String, Data)]) -> Data {
    var body = Data()
    var directory = Data()
    for (name, data) in files {
      let fields = le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(UInt32(data.count)) + le32(UInt32(data.count))
      let offset = UInt32(body.count)
      body += le32(0x0403_4b50) + le16(20) + fields + le16(UInt16(name.utf8.count)) + le16(0) + Data(name.utf8) + data
      directory += le32(0x0201_4b50) + le16(20) + le16(20) + fields + le16(UInt16(name.utf8.count))
      directory += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + Data(name.utf8)
    }
    return body + directory + le32(0x0605_4b50) + le16(0) + le16(0) + le16(UInt16(files.count))
      + le16(UInt16(files.count)) + le32(UInt32(directory.count)) + le32(UInt32(body.count)) + le16(0)
  }

  private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
  private static func le32(_ value: UInt32) -> Data { le16(UInt16(value & 0xFFFF)) + le16(UInt16(value >> 16)) }
}
