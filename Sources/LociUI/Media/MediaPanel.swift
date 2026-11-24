import LociModel
import SwiftUI

/// The highlights left on a video or podcast, in time order, under the thought on the whole of it; a click
/// plays from one.
struct MediaNotesPage: View {
  let item: Item
  let notes: [Note]
  let segments: [Transcript.Segment]
  let play: (Duration) -> Void
  let ask: (Note) -> Void
  @State private var selected: EntityID?

  var body: some View {
    let placed =
      notes
      .filter { !$0.isWhole }
      .sorted { ($0.locator.time?.start ?? .zero) < ($1.locator.time?.start ?? .zero) }
      .map { note in
        let index = note.locator.time.flatMap { TranscriptFollow.playing(in: segments, at: $0.start) } ?? 0
        return PlacedNote(note: note, range: NSRange(location: index, length: 1))
      }
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Spacing.xs) {
        WholeCard(item: item, thought: notes.first(where: \.isWhole)?.thought)
        ForEach(placed) { note in
          NoteCard(
            content: .item(item.id), placed: note, selected: selected == note.id, flash: nil, ask: { ask(note.note) }
          ) {
            selected = note.id
            if let time = note.note.locator.time { play(time.start) }
          }
        }
      }
      .padding(.horizontal, Spacing.s)
      .padding(.bottom, 20)
    }
    .scrollIndicators(.never)
  }
}

/// Where the transcript will be, before there is one.
struct TranscriptPending: View {
  let job: Job?
  let act: (JobLine.Fix) -> Void

  var body: some View {
    Group {
      if case .none = JobLine(job) {
        Image(systemName: Symbols.recognizing).font(.system(size: 22, weight: .light)).foregroundStyle(Palette.inkFaint)
      } else {
        JobDetail(line: JobLine(job), act: act)
      }
    }
    .padding(Spacing.l)
  }
}

/// Over the foot of the transcript while speech is recognized: how far along.
struct RecognitionCard: View {
  let progress: Fraction

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: 7) {
        Image(systemName: Symbols.recognizing).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
        Text(
          joining: Text(.loci("job.recognizing")), Text(verbatim: " \(Int((progress.value * 100).rounded()))%"))
      }
      .font(.system(size: 12, weight: .medium).monospaced())
      .foregroundStyle(Palette.inkMuted)
      GeometryReader { frame in Meter(share: progress.value, width: frame.size.width) }.frame(height: Size.meterHeight)
    }
    .padding(.horizontal, 14)
    .padding(.top, 11)
    .padding(.bottom, 13)
    .background(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.floating)
        .shadow(color: .black.opacity(0.1), radius: 12, y: 8)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(
        Palette.lineStrong, lineWidth: Size.hairline))
  }
}

/// The pages of the panel beside a video or a podcast.
enum MediaTab: Hashable {
  case transcript, keyPoints, conversation, highlights

  /// An episode's transcript is its page, so its panel has no transcript.
  static func all(for item: Item) -> [(value: MediaTab, title: LocalizedStringResource)] {
    let rest: [(value: MediaTab, title: LocalizedStringResource)] = [
      (.keyPoints, .loci("panel.keyPoints")), (.conversation, .loci("panel.conversation")),
      (.highlights, .loci("panel.highlights")),
    ]
    if case .audio = item.kind { return rest }
    return [(.transcript, .loci("panel.transcript"))] + rest
  }
}
