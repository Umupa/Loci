import LociModel
import SwiftUI

/// What an episode's page shows and what it can do.
struct EpisodeModel {
  let item: Item
  let player: Player
  let length: Duration
  let transcript: ReadableTranscript?
  let chapters: [Outline.Chapter]
  let notes: [Note]
  let mode: Binding<SubtitleMode>
  /// Still being recognized: more sentences come.
  let growing: Bool
  let actions: (ReadableTranscript) -> PassageActions
  let toggle: () -> Void
  let play: (Duration) -> Void
}

/// A podcast episode: the head with a small cover and the play button, the chapters, then the transcript in
/// paragraphs of talk. The sentence playing is washed in amber and kept in view until the reader scrolls; a
/// click plays from a sentence; a drag across sentences chooses them for a highlight or a question.
struct EpisodePage<Pending: View>: View {
  @Environment(\.reducesMotion) private var reduceMotion
  let model: EpisodeModel
  @Binding var follow: TranscriptFollow
  @Binding var chosen: ClosedRange<Int>?
  @ViewBuilder let pending: () -> Pending
  @State private var lines: [Int: [CGRect]] = [:]
  @State private var visible = CGRect.zero
  @State private var dragStart: Int?
  @State private var position = ScrollPosition(idType: String.self)

  private static var space: String { "episode" }

  var body: some View {
    let paragraphs = model.transcript.map { TranscriptParagraph.of($0.segments, chapters: model.chapters) } ?? []
    let playing = playingSentence
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        EpisodeHead(
          item: model.item, length: model.length, playing: model.player.playing, canPlay: model.player.canPlay,
          mode: model.transcript?.translation == nil ? nil : model.mode, toggle: model.toggle)
        if !model.chapters.isEmpty {
          EpisodeChapters(
            chapters: model.chapters, current: model.chapters.last { $0.start <= model.player.time },
            moving: model.player.playing, play: model.play
          )
          .padding(.top, Spacing.l)
          .padding(.horizontal, -Spacing.xs)
        }
        Rectangle().fill(Palette.line).frame(height: Size.hairline).padding(.vertical, Spacing.l)
        if let transcript = model.transcript {
          transcriptView(transcript, paragraphs: paragraphs, playing: playing)
        } else {
          pending().frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: Size.episodeColumn)
      .padding(.horizontal, Spacing.xl)
      .padding(.top, 60)
      .padding(.bottom, Spacing.xxl)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .topLeading) { passageBar }
      .coordinateSpace(.named(Self.space))
    }
    .scrollPosition($position)
    .scrollIndicators(.never)
    .onScrollPhaseChange { _, phase in
      if phase == .interacting { follow.scrolledByHand() }
    }
    .onScrollGeometryChange(for: CGRect.self, of: { $0.visibleRect.integral }) { _, rect in
      visible = rect
    }
    .onPreferenceChange(SentenceLines.self) { found in
      lines = found
      keepInView(paragraphs)
    }
    .onChange(of: playing) { keepInView(paragraphs) }
    .onChange(of: follow) { keepInView(paragraphs) }
    .onChange(of: model.player.playing) { keepInView(paragraphs) }
    .overlay(alignment: .bottom) {
      if !follow.following, playing != nil {
        BackToPlaying { follow.resume() }.padding(.bottom, Spacing.m).transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : Motion.quick, value: follow.following)
  }

  private var playingSentence: Int? {
    model.transcript.flatMap { TranscriptFollow.playing(in: $0.segments, at: model.player.time) }
  }

  private func transcriptView(
    _ transcript: ReadableTranscript, paragraphs: [TranscriptParagraph], playing: Int?
  ) -> some View {
    LazyVStack(alignment: .leading, spacing: Spacing.l) {
      ForEach(paragraphs) { paragraph in
        EpisodeParagraph(
          paragraph: paragraph, sentences: words(of: paragraph, in: transcript),
          translation: model.mode.wrappedValue == .both ? paragraph.translation(in: transcript) : nil,
          speaker: paragraph.speaker.map {
            SpeakerName(item: model.item.id, number: $0, name: transcript.transcript.name(ofSpeaker: $0))
          },
          playing: playing.flatMap { paragraph.sentences.contains($0) ? $0 : nil },
          chosen: chosen, noted: noted(paragraph, in: transcript), space: Self.space
        )
        .equatable()
        .id(Self.id(of: paragraph))
      }
      if model.growing { GrowingLines() }
    }
    .contentShape(Rectangle())
    .gesture(choosing)
    .onTapGesture(coordinateSpace: .named(Self.space)) { point in
      guard let index = sentence(at: point) else { return }
      chosen = nil
      follow.resume()
      model.play(transcript.segments[index].start)
    }
  }

  /// The words each sentence shows: the translation alone when only it shows and there is one.
  private func words(of paragraph: TranscriptParagraph, in transcript: ReadableTranscript) -> [(
    index: Int, text: String
  )] {
    paragraph.sentences.map { index in
      let text =
        model.mode.wrappedValue == .translation
        ? transcript.translated(index) ?? transcript.segments[index].text : transcript.segments[index].text
      return (index, text)
    }
  }

  private func noted(_ paragraph: TranscriptParagraph, in transcript: ReadableTranscript) -> Set<Int> {
    Set(paragraph.sentences.filter { index in model.notes.contains { $0.covers(transcript.segments[index]) } })
  }

  private static func id(of paragraph: TranscriptParagraph) -> String { "p\(paragraph.id)" }

  @ViewBuilder private var passageBar: some View {
    if let chosen, dragStart == nil, let transcript = model.transcript,
      let end = Self.union(lines[chosen.upperBound])
    {
      PassageBar(
        actions: model.actions(transcript), range: NSRange(location: chosen.lowerBound, length: chosen.count),
        typing: {},
        done: { self.chosen = nil }
      )
      .background(Capsule().fill(Palette.floating).shadow(color: .black.opacity(0.18), radius: 18, y: 12))
      .offset(x: end.minX, y: end.maxY + Spacing.xs)
    }
  }

  /// Following leaves the page where it is while the sentence playing is in view, and brings it a third of
  /// the way down once it leaves; a paragraph not drawn yet is brought in first.
  private func keepInView(_ paragraphs: [TranscriptParagraph]) {
    guard follow.following, model.player.playing, visible.height > 0, let playing = playingSentence else { return }
    let move = reduceMotion ? nil : Motion.standard
    if let frame = Self.union(lines[playing]) {
      guard frame.minY < visible.minY + Spacing.xxl || frame.maxY > visible.maxY - Self.coveredBelow else { return }
      withAnimation(move) { position.scrollTo(y: max(frame.minY - visible.height / 3, 0)) }
    } else if let paragraph = paragraphs.first(where: { $0.sentences.contains(playing) }) {
      withAnimation(move) { position.scrollTo(id: Self.id(of: paragraph), anchor: .top) }
    }
  }

  /// The foot of the page under the play bar and «back to playing».
  private static var coveredBelow: CGFloat { 90 }

  private static func union(_ rects: [CGRect]?) -> CGRect? {
    guard let rects, let first = rects.first else { return nil }
    return rects.dropFirst().reduce(first) { $0.union($1) }
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
    lines.first { $0.value.contains { $0.insetBy(dx: -2, dy: -3).contains(point) } }?.key
  }
}

/// Faint bars after the last paragraph while more is being recognized.
private struct GrowingLines: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Capsule().fill(Palette.fillStrong).frame(height: 10).frame(maxWidth: .infinity).padding(.trailing, 40)
      Capsule().fill(Palette.fill).frame(height: 10).frame(width: 220)
    }
  }
}
