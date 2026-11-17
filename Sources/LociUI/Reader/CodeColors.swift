import AppKit
import HighlightSwift

/// Colors for the words of a code block, by what each word is, from HighlightSwift's grammars.
enum CodeColors {
  /// Built once; grammars load lazily, one language at a time.
  private static let highlighter = try? Highlighter.allLanguages()

  /// Ranges in `code`, in UTF-16 units, with their color. A block with no language, or one HighlightSwift
  /// does not know, stays one color.
  static func colors(of code: String, language: String?) -> [(NSRange, NSColor)] {
    guard let language = language?.lowercased(), !language.isEmpty, let highlighter,
      let result = try? highlighter.highlight(code, language: language)
    else { return [] }
    return result.tokens.compactMap { token in
      color(of: token.kind).map { (NSRange(token.range, in: code), $0) }
    }
  }

  /// Some kinds are scopes around other words, such as a whole function header; those stay uncolored so
  /// only the words inside are colored.
  private static func color(of kind: TokenKind) -> NSColor? {
    switch kind {
    case .keyword, .meta, .tag: Tones.codeKeyword
    case .string, .regexp, .symbol: Tones.codeString
    case .number, .literal: Tones.codeNumber
    case .type, .title, .builtIn, .attribute: Tones.codeName
    case .comment: Tones.inkMuted
    default: nil
    }
  }
}
