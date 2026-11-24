import Foundation
import LociModel

/// A plain-text book: decoded from UTF-8, UTF-16 or GB18030, cut into chapters at lines such as `第一章`,
/// with lines that only wrap a paragraph joined back together. Each chapter is served as an XHTML page.
struct TextBook {
  struct Chapter: Equatable {
    let title: String
    let paragraphs: [String]
  }

  let chapters: [Chapter]
  let language: String?

  /// Text without chapter headings is cut at paragraphs into parts about this long.
  static let partLength = 20_000

  init(_ data: Data, title: String) throws(BookProblem) {
    guard let text = Self.decode(data) else { throw .notABook }
    let lines = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n").split(
      separator: "\n", omittingEmptySubsequences: false
    ).map(String.init)
    guard lines.contains(where: { !$0.trimmed.isEmpty }) else { throw .notABook }
    var chapters: [(title: String?, lines: [String])] = [(nil, [])]
    for line in lines {
      if Self.isHeading(line) {
        chapters.append((line.trimmed, []))
      } else {
        chapters[chapters.count - 1].lines.append(line)
      }
    }
    let style = Self.Style(lines)
    var made: [Chapter] = []
    for chapter in chapters {
      let paragraphs = style.paragraphs(chapter.lines)
      if let heading = chapter.title {
        made.append(Chapter(title: heading, paragraphs: paragraphs))
      } else if !paragraphs.isEmpty {
        made += Self.parts(paragraphs, title: title, numbered: chapters.count == 1)
      }
    }
    self.chapters = made
    let letters = text.unicodeScalars.prefix(20_000).filter { $0.properties.isAlphabetic }
    let han = letters.filter { $0.properties.isIdeographic }.count
    language = !letters.isEmpty && han * 3 > letters.count ? "zh" : nil
  }

  static func decode(_ data: Data) -> String? {
    if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
    if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
      return String(data: data, encoding: .utf16)
    }
    if let text = String(data: data, encoding: .utf8) { return text }
    let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    return String(data: data, encoding: String.Encoding(rawValue: gb18030))
  }

  static func isHeading(_ line: String) -> Bool {
    let text = line.trimmed
    guard !text.isEmpty, text.count <= 40 else { return false }
    return text.wholeMatch(of: /第[0-9０-９零〇一二三四五六七八九十百千万两]+[章回节節卷集部篇](\s.*|[:：].*)?/) != nil
      || text.wholeMatch(of: /(?i)chapter\s+([0-9]+|[ivxlc]+|[a-z]+)\b.*/) != nil
  }

  private static func parts(_ paragraphs: [String], title: String, numbered: Bool) -> [Chapter] {
    var parts: [[String]] = [[]]
    var length = 0
    for paragraph in paragraphs {
      if length >= partLength {
        parts.append([])
        length = 0
      }
      parts[parts.count - 1].append(paragraph)
      length += paragraph.count
    }
    if parts.count == 1 || !numbered { return [Chapter(title: title, paragraphs: parts.flatMap { $0 })] }
    return parts.enumerated().map { Chapter(title: String($0.offset + 1), paragraphs: $0.element) }
  }

  /// How the file marks where a paragraph starts.
  enum Style {
    /// A blank line between paragraphs; the lines in between only wrap.
    case blankLines
    /// Each paragraph starts indented; the lines in between only wrap.
    case indented
    /// Every line is a paragraph.
    case lines

    init(_ lines: [String]) {
      let filled = lines.filter { !$0.trimmed.isEmpty }
      let blank = lines.count - filled.count
      let indented = filled.filter(Self.startsIndented).count
      if blank * 4 >= filled.count, filled.count > blank + blank / 2 {
        self = .blankLines
      } else if indented * 10 >= filled.count, indented * 4 < filled.count * 3 {
        self = .indented
      } else {
        self = .lines
      }
    }

    static func startsIndented(_ line: String) -> Bool {
      line.hasPrefix("\u{3000}") || line.hasPrefix("  ") || line.hasPrefix("\t")
    }

    func paragraphs(_ lines: [String]) -> [String] {
      var paragraphs: [String] = []
      var current: String?
      func close() {
        if let text = current, !text.isEmpty { paragraphs.append(text) }
        current = nil
      }
      for line in lines {
        let text = line.trimmed
        if text.isEmpty {
          close()
          continue
        }
        switch self {
        case .lines:
          close()
          current = text
        case .indented where Self.startsIndented(line):
          close()
          current = text
        case .indented, .blankLines:
          current = current.map { TextBook.join($0, text) } ?? text
        }
      }
      close()
      return paragraphs
    }
  }

  static func join(_ first: String, _ second: String) -> String {
    guard let last = first.unicodeScalars.last, let next = second.unicodeScalars.first else { return first + second }
    return last.isWide || next.isWide ? first + second : first + " " + second
  }

  static func path(of chapter: Int) -> String { "chapter-\(chapter).xhtml" }

  static func chapter(in path: String) -> Int? {
    path.wholeMatch(of: /chapter-([0-9]+)\.xhtml/).flatMap { Int($0.1) }
  }

  func page(_ index: Int) -> Data {
    let chapter = chapters[index]
    let language = language.map { " lang=\"\($0)\" xml:lang=\"\($0)\"" } ?? ""
    var html = """
      <?xml version="1.0" encoding="utf-8"?>
      <html xmlns="http://www.w3.org/1999/xhtml"\(language)><head><title>\(Self.escape(chapter.title))</title></head>
      <body><h2>\(Self.escape(chapter.title))</h2>

      """
    for paragraph in chapter.paragraphs { html += "<p>\(Self.escape(paragraph))</p>\n" }
    html += "</body></html>\n"
    return Data(html.utf8)
  }

  var contents: BookContents {
    let pages = chapters.indices.map { BookContents.Chapter(path: Self.path(of: $0), length: page($0).count) }
    return BookContents(
      chapters: pages,
      toc: chapters.enumerated().map { .init(title: $0.element.title, depth: 0, chapter: $0.offset) },
      language: language)
  }

  static func escape(_ text: String) -> String {
    text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
  }
}

extension String {
  fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Unicode.Scalar {
  fileprivate var isWide: Bool {
    properties.isIdeographic || (0x3000...0x303F).contains(value) || (0xFF00...0xFFEF).contains(value)
  }
}
