import AppKit

/// How the reader sets text. Sizes follow `Typography`; AppKit needs fonts and paragraph styles, not SwiftUI fonts.
enum ReadingStyle {
  static let bodySize: CGFloat = 15
  static var body: NSFont { NSFont.systemFont(ofSize: bodySize) }
  static var code: NSFont { NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) }
  static let lineSpacing: CGFloat = 7
  static let paragraphSpacing: CGFloat = 14
  static let itemSpacing: CGFloat = 4
  static let listIndent: CGFloat = 22
  static let quoteIndent: CGFloat = 18
  static let codePadding: CGFloat = 12
  static let tableGap: CGFloat = 24
  /// Room above and below the column, so the first and last lines do not touch the window's edges.
  static let inset = CGSize(width: 0, height: 40)

  static func heading(_ level: Int) -> NSFont {
    let size: CGFloat =
      switch level {
      case 1: 24
      case 2: 19
      case 3: 16.5
      default: bodySize
      }
    return NSFont.systemFont(ofSize: size, weight: .semibold)
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
  /// A table's header row: a hairline under it.
  case tableHeader

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
