import AppKit
import SwiftUI
import Textual

/// The serif: New York for Latin letters, Songti for Chinese.
///
/// Chinese in the system serif falls back to Songti, and CoreText then sets each full-width mark it took
/// from that fallback half an em wider than Songti itself does, so `Loci，住在` reads `Loci，  住在`. Chinese
/// is therefore given Songti outright, run by run, and never left to the fallback.
enum Serif {
  /// A size and weight of the serif.
  struct Face: Sendable {
    let size: CGFloat
    var weight: Font.Weight = .regular

    /// For Latin letters and everything else that is not Chinese.
    var latin: Font { .system(size: size, weight: weight, design: .serif) }
    /// Songti has a regular and a bold; asking the family for a weight between does not reach the bold.
    var cjk: Font { .custom(Serif.songti(bold: Self.bold.contains(weight)), size: size) }

    private static let bold: Set<Font.Weight> = [.semibold, .bold, .heavy, .black]
  }

  /// Where the Chinese, Japanese and Korean characters and their punctuation are.
  static func cjkRuns<Characters: BidirectionalCollection<Character>>(in characters: Characters)
    -> [Range<Characters.Index>]
  {
    var runs: [Range<Characters.Index>] = []
    var start: Characters.Index?
    for index in characters.indices {
      let cjk = characters[index].unicodeScalars.first.map(isCJK) ?? false
      if cjk, start == nil {
        start = index
      } else if !cjk, let open = start {
        runs.append(open..<index)
        start = nil
      }
    }
    if let open = start { runs.append(open..<characters.endIndex) }
    return runs
  }

  static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    cjkBlocks.contains { $0.contains(scalar.value) }
  }

  /// Han, kana, hangul, and the punctuation and full-width forms set with them.
  private static let cjkBlocks: [ClosedRange<UInt32>] = [
    0x1100...0x11FF, 0x2E80...0x2FDF, 0x3000...0x30FF, 0x3130...0x318F, 0x31C0...0x31FF, 0x3200...0x4DBF,
    0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFE10...0xFE1F, 0xFE30...0xFE4F, 0xFF00...0xFFEF,
    0x20000...0x2FA1F,
  ]

  /// `text` in the serif at `face`, Chinese in Songti.
  static func attributed(_ text: String, _ face: Face) -> AttributedString {
    var attributed = AttributedString(text)
    setFonts(in: &attributed, face) { _ in true }
    return attributed
  }

  /// Gives the runs `included` picks the serif at `face`, and the Chinese in them Songti.
  static func setFonts(
    in attributed: inout AttributedString, _ face: Face, where included: (AttributedString.Runs.Run) -> Bool
  ) {
    for run in attributed.runs where included(run) {
      attributed[run.range].font = face.latin
      for range in cjkRuns(in: attributed[run.range].characters) { attributed[range].font = face.cjk }
    }
  }

  /// Whether a run of parsed Markdown is in a heading.
  static func isHeading(_ run: AttributedString.Runs.Run) -> Bool {
    run.presentationIntent?.components.contains { if case .header = $0.kind { true } else { false } } ?? false
  }

  /// Puts Songti under the Chinese wherever AppKit text is set in the system serif, at the same size and
  /// weight.
  static func setCJKFonts(in text: NSMutableAttributedString) {
    let whole = text.string
    let family = NSFont.serif(ofSize: NSFont.systemFontSize).familyName
    var changes: [(NSRange, NSFont)] = []
    text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      guard let font = value as? NSFont, font.familyName == family, let span = Range(range, in: whole) else { return }
      let songti = songti(matching: font)
      for run in cjkRuns(in: whole[span]) { changes.append((NSRange(run, in: whole), songti)) }
    }
    for (range, font) in changes { text.addAttribute(.font, value: font, range: range) }
  }

  private static func songti(matching font: NSFont) -> NSFont {
    let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
    let weight = traits?[.weight] as? CGFloat ?? 0
    return NSFont(name: songti(bold: weight >= NSFont.Weight.semibold.rawValue), size: font.pointSize) ?? font
  }

  static func songti(bold: Bool) -> String {
    bold ? "STSongti-SC-Bold" : "STSongti-SC-Regular"
  }
}

extension Text {
  /// Words in the serif, Chinese in Songti.
  init(serif text: String, _ face: Serif.Face) {
    self.init(Serif.attributed(text, face))
  }
}

/// Markdown whose paragraphs and lists are set in the serif, Chinese in Songti. Headings keep the font their
/// style gives them.
struct SerifMarkdown: MarkupParser {
  let face: Serif.Face

  func attributedString(for input: String) throws -> AttributedString {
    var parsed = try AttributedStringMarkdownParser.markdown().attributedString(for: input)
    Serif.setFonts(in: &parsed, face) { !Serif.isHeading($0) }
    return parsed
  }
}
