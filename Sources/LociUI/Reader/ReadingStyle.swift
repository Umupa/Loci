import AppKit

/// How the reader sets text. AppKit needs fonts and paragraph styles, not SwiftUI fonts.
enum ReadingStyle {
  /// A size up from conversation text: a lesson or an article is read at length, Chinese at about 33 characters a line.
  static let bodySize: CGFloat = 17
  static var body: NSFont { NSFont.systemFont(ofSize: bodySize) }
  static var code: NSFont { NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) }
  static let lineSpacing: CGFloat = 10
  /// An article's title.
  static let articleTitleSize: CGFloat = 30
  static let paragraphSpacing: CGFloat = 20
  /// A table's cells, a step down from the text so columns fit more.
  static let tableSize: CGFloat = 14.5
  static let itemSpacing: CGFloat = 4
  static let listIndent: CGFloat = 22
  static let quoteIndent: CGFloat = 18
  static let codePadding: CGFloat = 12
  /// Room above and below the column, so the first and last lines do not touch the window's edges.
  static let inset = CGSize(width: 0, height: Size.readingTop)

  /// Titles are set in the serif. Sections follow the text: in the serif beside serif text, in the sans-serif
  /// beside sans-serif text, so a section heading never reads lighter than the headings under it.
  static func heading(_ level: Int, serif: Bool) -> NSFont {
    switch (level, serif) {
    case (1, _): NSFont.serif(ofSize: 32, weight: .semibold)
    case (2, true): NSFont.serif(ofSize: 21, weight: .semibold)
    case (2, false): NSFont.systemFont(ofSize: 21, weight: .semibold)
    case (3, _): NSFont.systemFont(ofSize: 18, weight: .semibold)
    default: NSFont.systemFont(ofSize: bodySize, weight: .semibold)
    }
  }

  /// Room before a heading, after the paragraph before it has taken its own, and after it.
  static func headingSpacing(_ level: Int) -> (before: CGFloat, after: CGFloat) {
    switch level {
    case 1: (paragraphSpacing, 30)
    case 2: (26, 12)
    case 3: (10, 8)
    default: (6, 6)
    }
  }

  static func bold(_ font: NSFont) -> NSFont {
    styled(font, .bold)
  }

  static func italic(_ font: NSFont) -> NSFont {
    styled(font, .italic)
  }

  private static func styled(_ font: NSFont, _ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
    NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)), size: 0)
      ?? font
  }
}

/// What the reader draws behind or beside a paragraph, besides its text.
enum BlockDecoration: String {
  /// One line of a code block. The block's first and last lines round the background's corners.
  case codeOnly, codeFirst, codeMiddle, codeLast
  /// A paragraph inside a block quote: a bar at its leading edge.
  case quote
  /// A thematic break: a hairline across the column.
  case rule
  static let key = NSAttributedString.Key("lociBlock")

  static func code(line: Int, of count: Int) -> BlockDecoration {
    switch (line == 0, line == count - 1) {
    case (true, true): .codeOnly
    case (true, false): .codeFirst
    case (false, true): .codeLast
    case (false, false): .codeMiddle
    }
  }
}
