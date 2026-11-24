import AppKit
import LociModel

/// The translation an article is shown with, and how.
struct ShownTranslation: Equatable {
  /// Translations by the Markdown of the passage they were made from.
  let passages: [String: String]
  let mode: SubtitleMode
  /// Which goes on top when both show.
  var order = SubtitleStyle.BilingualOrder.originalAbove
}

/// How the shown text lines up with the original when translations sit beside or in place of passages.
///
/// Quotes are always taken from and found in the original, so a highlight made while reading the translation
/// is still found when the original is shown alone, and the other way round. A place inside a translation
/// stands for the whole passage it translates.
struct TranslationMap: Equatable {
  /// The text with no translation in it, as it reads when only the original is shown.
  let original: String
  private let replacements: [Replacement]

  /// A translation in the shown text, the original characters it hides, and the passage it translates.
  struct Replacement: Equatable {
    /// The translation's words, without the line break after them.
    let shown: NSRange
    /// How much of the shown text it takes, line break included.
    let advance: Int
    /// Empty when the translation sits beside the passage.
    let replaced: NSRange
    let source: NSRange
  }

  /// How a paragraph goes into the text.
  enum Part {
    case original
    /// Part of the original that is not shown.
    case hidden
    /// A translation shown after `source`.
    case beside(NSRange)
    /// A translation shown before `source`, which comes next.
    case above(NSRange)
    /// A translation shown in place of `source`, which is hidden.
    case instead(NSRange)
  }

  static let identity = TranslationMap(original: "", replacements: [])

  private init(original: String, replacements: [Replacement]) {
    self.original = original
    self.replacements = replacements
  }

  var isIdentity: Bool { replacements.isEmpty }

  /// Where a range of the original is shown. A range inside a hidden passage is shown as its translation.
  func shown(_ range: NSRange) -> NSRange {
    let start = shown(range.location, end: false)
    let end = shown(NSMaxRange(range), end: true)
    return NSRange(location: start, length: max(end - start, 0))
  }

  /// The range of the original a shown range stands for. An end inside a translation reaches to that end of
  /// the passage it translates.
  func original(_ range: NSRange) -> NSRange {
    let start = original(range.location, end: false)
    let end = original(NSMaxRange(range), end: true)
    return NSRange(location: start, length: max(end - start, 0))
  }

  private func shown(_ location: Int, end: Bool) -> Int {
    var delta = 0
    for replacement in replacements {
      let replaced = replacement.replaced
      let inside =
        end
        ? replaced.location < location && location <= NSMaxRange(replaced)
        : replaced.location <= location && location < NSMaxRange(replaced)
      if inside { return end ? NSMaxRange(replacement.shown) : replacement.shown.location }
      let before = end ? location <= replaced.location : location < replaced.location
      if before { break }
      delta += replacement.advance - replaced.length
    }
    return location + delta
  }

  private func original(_ location: Int, end: Bool) -> Int {
    var delta = 0
    for replacement in replacements {
      let first = replacement.shown.location
      let last = first + replacement.advance
      let inside = end ? first < location && location <= last : first <= location && location < last
      if inside { return end ? NSMaxRange(replacement.source) : replacement.source.location }
      if location <= first { break }
      delta += replacement.advance - replacement.replaced.length
    }
    return location - delta
  }

  /// Collects the original and the replacements while a text is set.
  final class Builder {
    var original = ""
    private var replacements: [Replacement] = []

    /// Appends `line` to `output` as `part`, and returns where it is in the original, without its line break.
    func add(_ line: NSAttributedString, as part: Part, to output: NSMutableAttributedString) -> NSRange {
      let length = line.length
      let shown = NSRange(location: output.length, length: max(length - 1, 0))
      let here = (original as NSString).length
      switch part {
      case .original:
        output.append(line)
        original += line.string
        return NSRange(location: here, length: max(length - 1, 0))
      case .hidden:
        original += line.string
        return NSRange(location: here, length: max(length - 1, 0))
      case .beside(let source):
        output.append(line)
        replacements.append(
          Replacement(
            shown: shown, advance: length, replaced: NSRange(location: NSMaxRange(source) + 1, length: 0),
            source: source))
        return source
      case .above(let source):
        output.append(line)
        replacements.append(
          Replacement(
            shown: shown, advance: length, replaced: NSRange(location: source.location, length: 0), source: source))
        return source
      case .instead(let source):
        output.append(line)
        replacements.append(
          Replacement(
            shown: shown, advance: length, replaced: NSRange(location: source.location, length: source.length + 1),
            source: source))
        return source
      }
    }

    func finished(shownLength: Int) -> TranslationMap {
      var original = self.original
      if original.hasSuffix("\n") { original.removeLast() }
      let clamped = replacements.map { replacement in
        Replacement(
          shown: NSRange(
            location: replacement.shown.location,
            length: max(min(NSMaxRange(replacement.shown), shownLength) - replacement.shown.location, 0)),
          advance: replacement.advance, replaced: replacement.replaced, source: replacement.source)
      }
      return TranslationMap(original: original, replacements: clamped)
    }
  }
}

extension ReadingText {
  /// The text without translations, where quotes are taken from and found.
  var original: String { map.isIdentity ? plain : map.original }

  /// Where a quote is shown, or `nil` when its words are gone.
  func range(of quote: TextQuote) -> NSRange? {
    originalRange(of: quote).map { map.shown($0) }
  }

  func originalRange(of quote: TextQuote) -> NSRange? {
    let original = original
    guard let found = quote.range(in: original) else { return nil }
    return NSRange(found, in: original)
  }

  /// The original words a shown range stands for, quoted with their context, and the pictures among them.
  func quote(_ range: NSRange) -> ReaderPassage? {
    quoteOriginal(map.original(range)).map {
      ReaderPassage(quote: $0.quote, excerpt: $0.excerpt, pictures: pictures(in: range))
    }
  }

  func quoteOriginal(_ range: NSRange) -> ReaderPassage? {
    let original = original
    guard let words = Range(range, in: original), let quote = try? TextQuote(quoting: words, in: original)
    else { return nil }
    return ReaderPassage(quote: quote, excerpt: ReaderPassage.words(String(original[words])), pictures: [])
  }

  /// The addresses of the pictures shown in `range`, in reading order.
  func pictures(in range: NSRange) -> [String] {
    var found: [String] = []
    guard NSMaxRange(range) <= string.length else { return found }
    string.enumerateAttribute(.readerPicture, in: range) { value, _, _ in
      if let address = value as? String { found.append(address) }
    }
    return found
  }
}

/// A passage chosen in the reading text: where it is, its words without the pictures among them, and those
/// pictures by their address in the item's text.
struct ReaderPassage: Equatable {
  let quote: TextQuote
  /// `nil` when only pictures were chosen.
  let excerpt: String?
  let pictures: [String]

  /// Text without the characters pictures stand on, trimmed; `nil` when nothing else is left.
  static func words(_ text: String) -> String? {
    let words = text.replacing("\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    return words.isEmpty ? nil : words
  }
}

extension NSAttributedString.Key {
  /// On the character a picture stands on: the address the item's text names the picture with.
  static let readerPicture = NSAttributedString.Key("lociPicture")
}
