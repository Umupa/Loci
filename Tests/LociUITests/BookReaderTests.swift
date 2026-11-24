import AppKit
import LociModel
import Testing
import WebKit

@testable import LociUI

/// BK-S5–BK-S10: the pages of a real web view turned, laid out again and followed.
@MainActor
@Suite(.onStage)
struct BookReaderTests {
  /// A reader of a sample book in a window off screen, and every file it asked for.
  @MainActor
  final class Bench {
    let reader: BookReader
    let window: NSWindow
    private let log = Asked()
    var asked: [String] { log.paths }

    @MainActor
    final class Asked {
      var paths: [String] = []
    }

    init(
      _ item: EntityID, books: SampleBooks, contents: BookContents? = nil, files: [String: Data]? = nil,
      width: Double = 1200, height: Double = 760, settings: BookSettings = .standard
    ) {
      let served = files ?? books.files[item] ?? [:]
      let log = self.log
      let bookFiles = BookFiles(item: item) { path in
        log.paths.append(path)
        guard let data = served[path] else { throw HostError.notFound(path) }
        return data
      }
      reader = BookReader(
        item: item, contents: contents ?? books.contents[item]!, files: bookFiles,
        layout: BookLayout(settings: settings, dark: false, width: width))
      window = NSWindow(
        contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: height), styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = reader.webView
      window.orderBack(nil)
    }

    func resize(to width: Double, settings: BookSettings = .standard) async {
      window.setContentSize(CGSize(width: width, height: window.frame.height))
      reader.webView.frame = CGRect(x: 0, y: 0, width: width, height: window.frame.height)
      await reader.relayout(BookLayout(settings: settings, dark: false, width: width))
    }

    func isShowing(_ spot: BookSpot) async throws -> Bool {
      guard spot.chapter == reader.chapter else { return false }
      let page = try await reader.webView.evaluateJavaScript(
        "loci.pageOf(\(BookReader.json(spot.node)), \(spot.character))")
      return page as? Int == reader.page
    }

    func script(_ source: String) async throws -> Any? {
      try await reader.webView.evaluateJavaScript(source)
    }

    func close() {
      window.orderOut(nil)
    }
  }

  /// BK-S5: a chapter turned to its end goes on into the next, and back again lands on the last page.
  @Test func turningPastAChaptersLastPageOpensTheNext() async throws {
    let books = try SampleBooks()
    let bench = Bench(books.nahan.id, books: books)
    await bench.reader.open(at: nil)
    #expect(bench.reader.chapter == 0)
    #expect(bench.reader.pages >= 2)

    for _ in 0..<bench.reader.pages { await bench.reader.turn(1) }
    #expect(bench.reader.chapter == 1)
    #expect(bench.reader.page == 0)

    await bench.reader.turn(-1)
    #expect(bench.reader.chapter == 0)
    #expect(bench.reader.page == bench.reader.pages - 1)
  }

  /// BK-S8, BK-S9: after the window narrows to one page or the text grows, the sentence that opened the page is
  /// still on the page shown.
  @Test func aChangeOfWidthOrSizeKeepsThePlaceOnThePage() async throws {
    let books = try SampleBooks()
    let bench = Bench(books.nahan.id, books: books)
    await bench.reader.show(books.contents[books.nahan.id]!.toc[2])
    await bench.reader.turn(1)
    let spot = try #require(bench.reader.spot)
    let wide = bench.reader.pages

    await bench.resize(to: 700)
    #expect(bench.reader.layout.columns == 1)
    #expect(bench.reader.pages > wide)
    #expect(try await bench.isShowing(spot))

    var larger = BookSettings.standard
    larger.size = 26
    larger.spacing = .loose
    await bench.resize(to: 700, settings: larger)
    #expect(try await bench.isShowing(spot))
  }

  /// BK-S8: a book opened again at its saved place shows the page that place is on.
  @Test func openingAtASavedPlaceShowsItsPage() async throws {
    let books = try SampleBooks()
    let first = Bench(books.nahan.id, books: books)
    await first.reader.open(at: nil)
    for _ in 0..<(first.reader.pages + 2) { await first.reader.turn(1) }
    let spot = try #require(first.reader.spot)

    let again = Bench(books.nahan.id, books: books)
    await again.reader.open(at: spot)

    #expect(again.reader.chapter == spot.chapter)
    #expect(again.reader.page == first.reader.page)
    #expect(spot.share.value > 0)
  }

  /// BK-S10: a note followed from the text, then back to the page it was followed from.
  @Test func followingANoteAndGoingBackReturnsToThePage() async throws {
    let books = try SampleBooks()
    let bench = Bench(books.nahan.id, books: books)
    await bench.reader.show(books.contents[books.nahan.id]!.toc[2])
    let spot = try #require(bench.reader.spot)

    await bench.reader.follow(try #require(URL(string: "loci-book://book/OPS/notes.xhtml#n1")))
    #expect(bench.reader.chapter == 2)
    #expect(bench.reader.back == spot)

    await bench.reader.goBack()
    #expect(bench.reader.chapter == 1)
    #expect(bench.reader.back == nil)
    #expect(try await bench.isShowing(spot))
  }

  /// BK-S7: the table of contents and the bar take the reader to a chapter.
  @Test func theContentsAndTheBarJumpToTheirPlace() async throws {
    let books = try SampleBooks()
    let contents = try #require(books.contents[books.nahan.id])
    let bench = Bench(books.nahan.id, books: books)
    await bench.reader.open(at: nil)

    await bench.reader.show(contents.toc[3])
    #expect(bench.reader.chapter == 2)

    await bench.reader.show(share: Fraction(0.3))
    #expect(bench.reader.chapter == contents.place(of: Fraction(0.3))?.chapter)
  }

  /// BK-S6: the book's own colours, faces and backgrounds give way to Loci's.
  @Test func theBooksOwnStylesGiveWayToLocis() async throws {
    let books = try SampleBooks()
    let bench = Bench(books.nahan.id, books: books)
    await bench.reader.show(books.contents[books.nahan.id]!.toc[2])

    let paragraph = try await bench.script("getComputedStyle(document.querySelector('p')).color") as? String
    let face = try await bench.script("getComputedStyle(document.querySelector('p')).fontFamily") as? String
    let table = try await bench.script("getComputedStyle(document.querySelector('table')).backgroundColor") as? String
    let indent = try await bench.script("getComputedStyle(document.querySelectorAll('p')[1]).textIndent") as? String

    #expect(paragraph == "rgb(29, 27, 24)")
    #expect(face?.contains("Papyrus") == false)
    #expect(table == "rgba(0, 0, 0, 0)")
    #expect(indent == "36px")
  }

  /// An English book justified by its own styles is set ragged, as columns this narrow leave wide gaps; its
  /// centred lines stay centred.
  @Test func englishTextIsSetRaggedButKeepsItsCentring() async throws {
    let books = try SampleBooks()
    let page = SampleBooks.page(
      "One", #"<p style="text-align: justify">Begin the morning.</p><p style="text-align: center">Book II</p>"#,
      language: "en")
    let contents = BookContents(chapters: [.init(path: "a.xhtml", length: page.count)], toc: [], language: "en")
    let bench = Bench(books.meditations.id, books: books, contents: contents, files: ["a.xhtml": page])

    await bench.reader.open(at: nil)

    let aligns = try await bench.script("[...document.querySelectorAll('p')].map(p => getComputedStyle(p).textAlign)")
    #expect(aligns as? [String] == ["start", "center"])
  }

  /// A chapter that is not well-formed XHTML is shown as HTML rather than as the parser's complaint.
  @Test func aChapterThatIsNotWellFormedIsStillShown() async throws {
    let books = try SampleBooks()
    let broken = Data("<html><body><p>未閉合的段落<br></p><p>第二段</body></html>".utf8)
    let contents = BookContents(chapters: [.init(path: "a.xhtml", length: broken.count)], toc: [], language: "zh")
    let bench = Bench(books.nahan.id, books: books, contents: contents, files: ["a.xhtml": broken])

    await bench.reader.open(at: nil)

    let text = try await bench.script("document.body.innerText") as? String
    #expect(text?.contains("第二段") == true)
    #expect(try await bench.script("loci.broken()") as? Bool == false)
  }

  /// Remote reading: the next chapter and the files it uses are fetched while this one is read.
  @Test func theNextChapterAndItsFilesAreFetchedAhead() async throws {
    let books = try SampleBooks()
    let bench = Bench(books.nahan.id, books: books)

    await bench.reader.open(at: nil)

    try await eventually("the next chapter fetched") { bench.asked.contains("OPS/c2.xhtml") }
    try await eventually("its style sheet fetched") { bench.asked.filter { $0 == "OPS/style.css" }.count == 1 }
  }

  @Test func filesAChapterUsesAreFoundBesideIt() {
    let page = Data(
      #"<link href="../css/a.css"/><img src="images/x%20y.png"/><a href="c3.xhtml#n">x</a><a href="https://e.com/a.png">"#
        .utf8)

    #expect(BookFiles.references(in: page, of: "OPS/text/c2.xhtml") == ["OPS/css/a.css", "OPS/text/images/x y.png"])
  }
}
