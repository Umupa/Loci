import SwiftUI
import Textual

/// What Loci says in one bubble: headings in serif, ordered lists numbered in amber, code, tables and
/// formulas. While it streams it grows a sentence at a time, and only its last heading or paragraph is drawn
/// again.
///
/// The words are one view for each of their pieces, so a long bubble lays out again only the piece that
/// changed. In a stack that already leaves `spacing` between its rows, the pieces take that room off the room
/// between them.
struct ReplyText: View {
  let text: String
  let streaming: Bool
  var size: CGFloat = 14
  var spacing: CGFloat = 0

  var body: some View {
    let chunks = ReplyChunks(DisplayMath.fenced(Self.settled(text, streaming: streaming))).chunks
    ForEach(chunks.indices, id: \.self) { index in
      let chunk = chunks[index]
      ReplyChunk(markdown: chunk.markdown, size: size)
        .frame(maxWidth: chunk.isFormula ? .infinity : nil, alignment: chunk.isFormula ? .center : .leading)
        .followsPointerForCode()
        .padding(.top, index == 0 ? 0 : Self.gap(above: chunk.opening, size: size) - spacing)
    }
  }

  /// A heading is this much larger than the words around it.
  static let headingScale: CGFloat = 18 / 14

  /// The room Textual leaves above a block of each kind: its default paragraph and code styles, and the
  /// headings of a reply.
  static func gap(above opening: ReplyChunks.Opening, size: CGFloat) -> CGFloat {
    switch opening {
    case .heading: ReplyHeading.above * headingScale * size
    case .code: 0.88 * size
    case .other: 0.8 * size
    }
  }

  /// What of a reply to show: all of it once it is complete, and up to the last finished sentence while it
  /// streams, so a sentence never appears half-written.
  nonisolated static func settled(_ text: String, streaming: Bool) -> String {
    guard streaming else { return text }
    guard let end = text.lastIndex(where: { "。！？；\n.!?".contains($0) }) else { return "" }
    return String(text[...end])
  }
}

/// One piece of a reply, laid out again only when its own text changes.
struct ReplyChunk: View, Equatable {
  let markdown: String
  var size: CGFloat = 14

  var body: some View {
    StructuredText(
      markdown, parser: ReplyMarkdown(headingFace: Serif.Face(size: size * ReplyText.headingScale, weight: .semibold))
    )
    .font(.system(size: size))
    .foregroundStyle(Palette.ink)
    .textual.headingStyle(ReplyHeading())
    .textual.orderedListMarker(AmberNumber())
    .textual.codeBlockStyle(CopyableCodeBlock())
    .textual.structuredTextStyle(.default)
    .textual.textSelection(.enabled)
  }
}

/// A reply's Markdown with formulas, its headings in the serif and the Chinese in them in Songti.
private struct ReplyMarkdown: MarkupParser {
  let headingFace: Serif.Face

  func attributedString(for input: String) throws -> AttributedString {
    var parsed = try AttributedStringMarkdownParser.markdown(syntaxExtensions: [.math]).attributedString(for: input)
    Serif.setFonts(in: &parsed, headingFace, where: Serif.isHeading)
    return parsed
  }
}

/// The room around a heading; its size is the reply's, scaled, and its face the serif.
private struct ReplyHeading: StructuredText.HeadingStyle {
  /// The room above a heading, in its own size.
  static let above: CGFloat = 0.2

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .textual.fontScale(ReplyText.headingScale)
      .textual.blockSpacing(.fontScaled(top: Self.above, bottom: 0.45))
  }
}

private struct AmberNumber: StructuredText.OrderedListMarker {
  func makeBody(configuration: Configuration) -> some View {
    Text(verbatim: "\(configuration.ordinal)")
      .font(.system(size: 11, weight: .semibold).monospaced())
      .foregroundStyle(Palette.accentInk)
      .frame(minWidth: 14, alignment: .leading)
  }
}

/// Text that a light sweeps across, for work still going on.
struct Shimmer: View {
  let text: Text

  var body: some View {
    TimelineView(.animation) { timeline in
      let phase =
        timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
      text.foregroundStyle(
        LinearGradient(
          colors: [Palette.inkFaint, Palette.ink, Palette.inkFaint],
          startPoint: UnitPoint(x: phase * 2 - 1.5, y: 0.5), endPoint: UnitPoint(x: phase * 2 - 0.5, y: 0.5)))
    }
  }

  private static let period = 1.8
}
