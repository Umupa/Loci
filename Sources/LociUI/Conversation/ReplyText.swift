import SwiftUI
import Textual

/// The mentor's reply, without a bubble: headings in serif, ordered lists numbered in amber. While it
/// streams it grows a sentence at a time, each new sentence fading in over the text already shown.
struct ReplyText: View {
  let text: String
  let streaming: Bool
  @State private var shown = ""
  @State private var arriving = ""
  @State private var progress = 1.0

  var body: some View {
    ZStack(alignment: .topLeading) {
      if progress < 1 { Self.rendered(shown) }
      Self.rendered(arriving).opacity(progress)
    }
    .onAppear {
      arriving = Self.settled(text, streaming: streaming)
      shown = arriving
    }
    .onChange(of: Self.settled(text, streaming: streaming)) { _, settled in
      shown = arriving
      arriving = settled
      progress = 0
      withAnimation(.easeOut(duration: Self.fade)) { progress = 1 }
    }
  }

  private static let fade = 0.45

  private static func rendered(_ markdown: String) -> some View {
    StructuredText(markdown: markdown, syntaxExtensions: [.math])
      .font(.system(size: 14))
      .foregroundStyle(Palette.ink)
      .textual.headingStyle(ReplyHeading())
      .textual.orderedListMarker(AmberNumber())
      .textual.structuredTextStyle(.default)
      .textual.textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// What of a reply to show: all of it once it is complete, and up to the last finished sentence while it
  /// streams, so a sentence never appears half-written.
  nonisolated static func settled(_ text: String, streaming: Bool) -> String {
    guard streaming else { return text }
    guard let end = text.lastIndex(where: { "。！？；\n.!?".contains($0) }) else { return "" }
    return String(text[...end])
  }
}

private struct ReplyHeading: StructuredText.HeadingStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .textual.fontScale(18 / 14)
      .fontDesign(.serif)
      .fontWeight(.semibold)
      .textual.blockSpacing(.fontScaled(top: 0.2, bottom: 0.45))
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
