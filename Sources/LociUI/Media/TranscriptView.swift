import LociModel
import SwiftUI

/// What the transcript draws for each sentence and between them.
struct TranscriptLayout {
  enum Line: Identifiable {
    /// A chapter beginning, with its time.
    case chapter(Outline.Chapter)
    /// A new speaker, named or numbered, with the time they start.
    case speaker(Int?, Duration)
    case sentence(Int)

    var id: String {
      switch self {
      case .chapter(let chapter): "c\(chapter.start.roundedMilliseconds)"
      case .speaker(_, let start): "p\(start.roundedMilliseconds)"
      case .sentence(let index): "s\(index)"
      }
    }
  }

  /// A chapter goes before the first sentence at or after its start; chapters with no sentence of their own
  /// in the transcript, such as before recognition has reached them, are left out. Speakers go before each sentence where
  /// the speaker changes, when speakers were told apart.
  static func lines(_ segments: [Transcript.Segment], chapters: [Outline.Chapter], showSpeakers: Bool) -> [Line] {
    var lines: [Line] = []
    var pending = chapters[...]
    var speaker: Int?
    for (index, segment) in segments.enumerated() {
      var begun: Outline.Chapter?
      while let chapter = pending.first, chapter.start <= segment.start {
        begun = chapter
        pending = pending.dropFirst()
      }
      if let begun { lines.append(.chapter(begun)) }
      if showSpeakers, let said = segment.speaker, said != speaker {
        lines.append(.speaker(said, segment.start))
        speaker = said
      }
      lines.append(.sentence(index))
    }
    return lines
  }
}

/// The transcript beside a player. The sentence playing is washed in amber and kept in view until the reader
/// scrolls; sentences a mentor picked out carry an amber bar; highlighted words are underlined. A click
/// plays from a sentence; a drag across sentences chooses them for a highlight or a question.
struct TranscriptView: View {
  let transcript: ReadableTranscript
  let chapters: [Outline.Chapter]
  let highlights: [ClosedRange<Duration>]
  let notes: [Note]
  let mode: SubtitleMode
  let playing: Int?
  /// Who speaks is shown over each change of speaker, and times go with the speakers instead of each sentence.
  var speakers = false
  /// Still being recognized: the last sentence may change, and more come.
  var growing = false
  @Binding var follow: TranscriptFollow
  @Binding var chosen: ClosedRange<Int>?
  let actions: PassageActions
  let play: (Int) -> Void
  @State private var frames: [Int: CGRect] = [:]
  @State private var dragStart: Int?
  @State private var position = ScrollPosition(idType: String.self)
  @State private var visible = CGRect.zero

  var body: some View {
    let lines = TranscriptLayout.lines(transcript.segments, chapters: chapters, showSpeakers: speakers)
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(lines) { line in
          view(of: line).id(line.id)
        }
        if growing { GhostLines() }
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 90)
      .coordinateSpace(.named(Self.space))
      .gesture(choosing)
    }
    .scrollPosition($position, anchor: .top)
    .scrollIndicators(.never)
    .mask(
      LinearGradient(
        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.025)], startPoint: .top,
        endPoint: .bottom)
    )
    .onScrollPhaseChange { _, phase in
      if phase == .interacting { follow.scrolledByHand() }
    }
    .onChange(of: playing, initial: true) { keepInView() }
    .onChange(of: follow) { keepInView() }
    .onChange(of: transcript.segments.count) { if growing { keepInView() } }
    .onScrollGeometryChange(for: CGRect.self, of: \.visibleRect) { _, rect in
      visible = rect
      keepInView()
    }
    .onPreferenceChange(SentenceFrames.self) { found in
      frames = found
      keepInView()
    }
    .overlay(alignment: .bottom) {
      if !follow.following, playing != nil {
        BackToPlaying { follow.resume() }.padding(.bottom, Spacing.m)
      }
    }
  }

  private static let space = "transcript"

  /// Following leaves the transcript where it is while the playing sentence is in view, and brings the
  /// sentence to the top once it leaves.
  private func keepInView() {
    guard follow.following, visible.height > 0, !frames.isEmpty else { return }
    if growing {
      position.scrollTo(edge: .bottom)
    } else if let playing {
      if let frame = frames[playing], frame.minY >= visible.minY,
        frame.maxY <= visible.maxY - Self.coveredBelow
      {
        return
      }
      position.scrollTo(id: TranscriptLayout.Line.sentence(playing).id, anchor: UnitPoint(x: 0, y: 0.02))
    }
  }

  /// The bottom of the transcript under the composer or the recognition card.
  private static let coveredBelow: CGFloat = 90

  @ViewBuilder private func view(of line: TranscriptLayout.Line) -> some View {
    switch line {
    case .chapter(let chapter):
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
        Text(verbatim: MediaTime.text(chapter.start)).font(Typography.mono).foregroundStyle(Palette.inkFaint)
          .frame(width: Size.timeColumn, alignment: .leading)
        Text(verbatim: chapter.title).font(Typography.chapterTitle).foregroundStyle(Palette.ink)
      }
      .padding(.top, 18)
      .padding(.bottom, Spacing.xxs)
      .padding(.leading, Spacing.xs)
      .padding(.trailing, 10)
    case .speaker(let number, let start):
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        Text(joining: Text(.loci("transcript.speaker")), Text(verbatim: number.map { " \($0)" } ?? ""))
          .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
        Text(verbatim: MediaTime.text(start)).font(Typography.mono).foregroundStyle(Palette.inkFaint)
      }
      .padding(.top, 18)
      .padding(.bottom, 2)
      .padding(.horizontal, 10)
    case .sentence(let index):
      sentence(index)
    }
  }

  private func sentence(_ index: Int) -> some View {
    let segment = transcript.segments[index]
    let now = index == playing
    let picked = highlights.contains { $0.lowerBound <= segment.start && segment.start < $0.upperBound }
    let isChosen = chosen?.contains(index) == true
    let noted = notes.contains { $0.covers(segment) }
    let lines = transcript.lines(index, mode: mode)
    let partial = growing && index == transcript.segments.count - 1
    return HStack(alignment: .top, spacing: Spacing.xxs) {
      if !speakers {
        Text(verbatim: MediaTime.text(segment.start))
          .font(Typography.mono)
          .foregroundStyle(now ? Palette.accentInk : Palette.inkFaint)
          .padding(.top, 5)
          .frame(width: Size.timeColumn, alignment: .leading)
      }
      VStack(alignment: .leading, spacing: 2) {
        ForEach(Array(lines.enumerated()), id: \.offset) { order, line in
          let first = order == 0
          SentenceText(text: line, first: first, chosen: isChosen && first, noted: noted && first)
            .foregroundStyle(first && !partial ? Palette.ink : Palette.inkMuted)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.leading, speakers ? 10 : Spacing.xs)
    .padding(.trailing, 10)
    .padding(.top, 6)
    .padding(.bottom, 7)
    .background(RoundedRectangle(cornerRadius: Radius.cover, style: .continuous).fill(now ? Palette.tint : .clear))
    .overlay(alignment: .leading) {
      if picked {
        RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 2.5).padding(.vertical, Spacing.xs)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let chosen, chosen.upperBound == index, dragStart == nil {
        PassageBar(
          actions: actions, range: NSRange(location: chosen.lowerBound, length: chosen.count), typing: {},
          done: { self.chosen = nil }
        )
        .background(Capsule().fill(Palette.floating).shadow(color: .black.opacity(0.18), radius: 18, y: 12))
        .offset(x: Size.timeColumn + Spacing.xs, y: Size.iconButton + Spacing.xs)
        .zIndex(2)
      }
    }
    .zIndex(chosen?.upperBound == index ? 2 : 0)
    .contentShape(Rectangle())
    .onTapGesture {
      chosen = nil
      follow.resume()
      play(index)
    }
    .background(
      GeometryReader { frame in
        Color.clear.preference(key: SentenceFrames.self, value: [index: frame.frame(in: .named(Self.space))])
      })
  }

  private var choosing: some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
      .onChanged { drag in
        guard let start = dragStart ?? sentence(at: drag.startLocation) else { return }
        dragStart = start
        let end = sentence(at: drag.location) ?? start
        chosen = min(start, end)...max(start, end)
      }
      .onEnded { _ in dragStart = nil }
  }

  private func sentence(at point: CGPoint) -> Int? {
    frames.first { $0.value.minY <= point.y && point.y <= $0.value.maxY }?.key
  }
}

/// The words of one line of a sentence: the original larger, its translation smaller; washed in amber while
/// chosen, banded along the foot of each line with a dot after when highlighted.
private struct SentenceText: View {
  let text: String
  let first: Bool
  let chosen: Bool
  let noted: Bool

  var body: some View {
    Text(verbatim: text)
      .font(first ? Typography.transcript : Typography.transcriptTranslation)
      .lineSpacing(first ? 4.5 : 4)
      .textRenderer(WordMarks(chosen: chosen, noted: noted))
  }
}

/// Draws a sentence's marks line by line, under its words.
private struct WordMarks: TextRenderer {
  let chosen: Bool
  let noted: Bool

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      let bounds = line.typographicBounds.rect
      if chosen {
        context.fill(
          Path(roundedRect: bounds.insetBy(dx: -2, dy: -1), cornerRadius: 2), with: .color(Palette.accent.opacity(0.24))
        )
      } else if noted {
        let band = bounds.height * 0.38
        context.fill(
          Path(
            roundedRect: CGRect(x: bounds.minX, y: bounds.maxY - band, width: bounds.width, height: band),
            cornerRadius: 2),
          with: .color(Palette.mark))
      }
      context.draw(line)
    }
    if noted, !chosen, let last = layout.last?.typographicBounds.rect {
      let dot = CGRect(x: last.maxX + 3, y: last.minY + last.height * 0.2, width: 5, height: 5)
      context.fill(Path(ellipseIn: dot), with: .color(Palette.accent))
    }
  }
}

/// Faint bars after the last sentence while more is being recognized.
private struct GhostLines: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Capsule().fill(Palette.fillStrong).frame(height: 9).frame(maxWidth: .infinity).padding(.trailing, 30)
      Capsule().fill(Palette.fill).frame(height: 9).frame(width: 180)
    }
    .padding(.top, Spacing.s)
    .padding(.leading, 52)
    .padding(.trailing, 10)
  }
}

/// Brings the sentence playing back into view, once the reader has scrolled away from it.
struct BackToPlaying: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: Symbols.backToPlaying).font(.system(size: 11, weight: .semibold)).foregroundStyle(
          Palette.accent)
        Text(.loci("transcript.backToPlaying")).font(Typography.button).foregroundStyle(Palette.ink)
      }
      .padding(.leading, 11)
      .padding(.trailing, 14)
      .frame(height: 30)
      .background(Capsule().fill(Palette.floating).shadow(color: .black.opacity(0.14), radius: 12, y: 8))
      .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    }
    .buttonStyle(PressStyle())
  }
}

private struct SentenceFrames: PreferenceKey {
  static let defaultValue: [Int: CGRect] = [:]

  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

extension Note {
  /// The note was left on this sentence of a transcript.
  func covers(_ segment: Transcript.Segment) -> Bool {
    guard let span = locator.time else { return false }
    let end = span.end ?? span.start
    return segment.start < end && span.start < segment.end || span.start == segment.start
  }
}
