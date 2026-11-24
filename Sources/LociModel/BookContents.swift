/// What a book is made of, for its reader: the chapters in reading order and the book's own table of contents.
public struct BookContents: Hashable, Codable, Sendable {
  public let chapters: [Chapter]
  /// The book's own table of contents, or one line per chapter when it has none.
  public let toc: [Entry]
  /// A BCP 47 tag, when the book says.
  public let language: String?

  public init(chapters: [Chapter], toc: [Entry], language: String?) {
    self.chapters = chapters
    self.toc = toc
    self.language = language
  }

  /// One page of the book's text, as `ReadBookFile` names it.
  public struct Chapter: Hashable, Codable, Sendable {
    public let path: String
    /// How many bytes of text it holds, for telling how far into the book a place is.
    public let length: Int

    public init(path: String, length: Int) {
      self.path = path
      self.length = length
    }
  }

  public struct Entry: Hashable, Codable, Sendable {
    public let title: String
    /// 0 for the top level.
    public let depth: Int
    public let chapter: Int
    /// The `id` in the chapter it points at; `nil` is the chapter's start.
    public let anchor: String?

    public init(title: String, depth: Int, chapter: Int, anchor: String? = nil) {
      self.title = title
      self.depth = depth
      self.chapter = chapter
      self.anchor = anchor
    }
  }

  /// How much of the book lies before `offset` bytes into `chapter`.
  public func share(chapter: Int, within fraction: Double) -> Fraction {
    let total = chapters.reduce(0) { $0 + $1.length }
    guard total > 0, chapters.indices.contains(chapter) else { return Fraction(0) }
    let before = chapters[..<chapter].reduce(0) { $0 + $1.length }
    return Fraction((Double(before) + Double(chapters[chapter].length) * Fraction(fraction).value) / Double(total))
  }

  /// The chapter a share of the whole book falls in, and how far into that chapter.
  public func place(of share: Fraction) -> (chapter: Int, within: Fraction)? {
    let total = chapters.reduce(0) { $0 + $1.length }
    guard total > 0 else { return chapters.isEmpty ? nil : (0, Fraction(0)) }
    var before = 0.0
    let target = share.value * Double(total)
    for (index, chapter) in chapters.enumerated() {
      let end = before + Double(chapter.length)
      if target < end || index == chapters.count - 1 {
        return (index, Fraction(chapter.length == 0 ? 0 : (target - before) / Double(chapter.length)))
      }
      before = end
    }
    return nil
  }

  /// The entry of the table of contents a chapter belongs to: the last one that starts at or before it.
  public func entry(for chapter: Int) -> Entry? {
    toc.last { $0.chapter <= chapter }
  }
}

/// Why a file cannot be taken in as a book.
public enum BookProblem: String, Error, Hashable, Codable, Sendable {
  /// Neither an EPUB nor a text file.
  case notABook
  /// The archive or its package is broken.
  case damaged
  /// Laid out page by page, like a picture book or a magazine.
  case fixedLayout
  /// Locked with DRM.
  case protected
}
