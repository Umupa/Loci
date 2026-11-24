import Foundation
import LociModel

/// Two small books served from memory: 吶喊 with a note to follow and the book's own clashing styles, and an
/// English book with a picture.
struct SampleBooks: Sendable {
  let nahan: Item
  let meditations: Item
  let contents: [EntityID: BookContents]
  let files: [EntityID: [String: Data]]

  static let kong = [
    "魯鎮的酒店的格局，是和別處不同的：都是當街一個曲尺形的大櫃臺，櫃裏面預備着熱水，可以隨時溫酒。",
    "做工的人，傍午傍晚散了工，每每花四文銅錢，買一碗酒，——這是二十多年前的事，現在每碗要漲到十文，——靠櫃外站着，熱熱的喝了休息；",
    "倘肯多花一文，便可以買一碟鹽煮筍，或者茴香豆，做下酒物了，如果出到十幾文，那就能買一樣葷菜，但這些顧客，多是短衣幫，大抵沒有這樣闊綽。",
    "只有穿長衫的，才踱進店面隔壁的房子裏，要酒要菜，慢慢地坐喝。",
  ]

  static let preface = [
    "我在年青時候也曾經做過許多夢，後來大半忘卻了，但自己也並不以爲可惜。",
    "所謂回憶者，雖說可以使人歡欣，有時也不免使人寂寞，使精神的絲縷還牽着己逝的寂寞的時光，又有什麼意味呢，而我偏苦於不能全忘卻，這不能全忘卻的一部分，到現在便成了《吶喊》的來由。",
  ]

  static func page(_ title: String, _ body: String, language: String = "zh") -> Data {
    Data(
      """
      <?xml version="1.0" encoding="utf-8"?>
      <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)" lang="\(language)">
      <head><title>\(title)</title><link rel="stylesheet" href="style.css"/></head>
      <body>\(body)</body></html>
      """.utf8)
  }

  static func paragraphs(_ lines: [String], times: Int) -> String {
    (0..<times).flatMap { _ in lines }.map { "<p>\($0)</p>" }.joined(separator: "\n")
  }

  init() throws {
    var entropy = Sample.Seeded()
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_400_000 + offset), entropy: &entropy)
    }
    nahan = try Item(id: id(1), kind: .book, title: "吶喊", authors: ["魯迅"], language: "zh")
    meditations = try Item(id: id(2), kind: .book, title: "Meditations", authors: ["Marcus Aurelius"], language: "en")
    let style = Data(
      "p { color: #c00; font-family: Papyrus; } table { background: white; } .name { text-decoration: underline; }"
        .utf8)
    let nahanFiles: [String: Data] = [
      "OPS/style.css": style,
      "OPS/c1.xhtml": Self.page("自序", "<h2>自序</h2>" + Self.paragraphs(Self.preface, times: 6)),
      "OPS/c2.xhtml": Self.page(
        "孔乙己",
        """
        <table style="background:#ffffff;width:100%"><tr><td style="text-align:center">孔乙己</td></tr>
        <tr><td style="text-align:center">作者：<span class="name">魯迅</span>　1919年3月</td></tr></table>
        <p>孔乙己是站着喝酒而穿長衫的唯一的人。<a id="r1" href="notes.xhtml#n1"><sup>1</sup></a></p>
        """ + Self.paragraphs(Self.kong, times: 14)),
      "OPS/notes.xhtml": Self.page("注釋", #"<h2>注釋</h2><p id="n1">1　長衫：舊時讀書人的服裝。</p>"#),
    ]
    let picture = SampleLibrary.picture("kleppmann") ?? Data()
    let english = [
      "Begin the morning by saying to thyself, I shall meet with the busy-body, the ungrateful, arrogant, deceitful, envious, unsocial.",
      "All these things happen to them by reason of their ignorance of what is good and evil.",
    ]
    let meditationsFiles: [String: Data] = [
      "text/style.css": style,
      "text/book2.xhtml": Self.page(
        "Book II",
        #"<h2>Book II</h2><p><img src="../images/figure.jpg" alt=""/></p>"#
          + Self.paragraphs(english, times: 10), language: "en"),
      "images/figure.jpg": picture,
    ]
    func contents(_ files: [String: Data], chapters: [String], toc: [BookContents.Entry], language: String)
      -> BookContents
    {
      BookContents(
        chapters: chapters.map { .init(path: $0, length: files[$0]?.count ?? 0) }, toc: toc, language: language)
    }
    self.contents = [
      nahan.id: contents(
        nahanFiles, chapters: ["OPS/c1.xhtml", "OPS/c2.xhtml", "OPS/notes.xhtml"],
        toc: [
          .init(title: "自序", depth: 0, chapter: 0), .init(title: "小說", depth: 0, chapter: 1),
          .init(title: "孔乙己", depth: 1, chapter: 1), .init(title: "注釋", depth: 0, chapter: 2),
        ], language: "zh"),
      meditations.id: contents(
        meditationsFiles, chapters: ["text/book2.xhtml"], toc: [.init(title: "Book II", depth: 0, chapter: 0)],
        language: "en"),
    ]
    files = [nahan.id: nahanFiles, meditations.id: meditationsFiles]
  }

  func file(_ path: String, of item: EntityID) throws(HostError) -> Data {
    guard let data = files[item]?[path] else { throw .notFound(path) }
    return data
  }
}

extension SampleLibrary {
  /// The library with the two books first: 吶喊 read a third of the way, at 孔乙己, and Meditations just
  /// begun, with a cover.
  func withBooks(_ books: SampleBooks) throws -> SampleLibrary {
    var library = self
    library.items = [books.nahan, books.meditations] + library.items
    library.covers[books.meditations.id] = "kleppmann"
    func at(_ item: Item, chapter: Int, share: Double, updated: Int64) throws -> ReadingState {
      ReadingState(
        position: .item(
          item.id, .spot(try BookSpot(chapter: chapter, node: [0], character: 0, share: Fraction(share)))),
        finished: false, updatedAt: Timestamp(millisecondsSince1970: 1_763_337_600_000 + updated * 1000))
    }
    library.states[books.nahan.id] = try at(books.nahan, chapter: 1, share: 0.34, updated: 40)
    library.states[books.meditations.id] = try at(books.meditations, chapter: 0, share: 0.02, updated: 10)
    return library
  }
}
