import LociModel
import SwiftUI

/// The top of an episode's page: a small cover beside the show, the title, the date and length, and the
/// play button, with which words the transcript shows once there is a translation.
struct EpisodeHead: View {
  let item: Item
  let length: Duration
  let playing: Bool
  let canPlay: Bool
  /// `nil` without a translation.
  let mode: Binding<SubtitleMode>?
  let toggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.l) {
      SquareCover(item: item, corner: Radius.cover)
        .frame(width: Size.episodeCover, height: Size.episodeCover)
        .overlay(
          RoundedRectangle(cornerRadius: Radius.cover, style: .continuous)
            .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 8)
      VStack(alignment: .leading, spacing: 0) {
        if let show = item.site ?? item.authors.first {
          SourceName(item: item, name: show).font(Typography.bodyEmphasis).foregroundStyle(Palette.inkMuted)
        }
        Text(serif: item.title, Typography.mediaTitle)
          .foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
        Text(verbatim: facts).font(Typography.mono).foregroundStyle(Palette.inkFaint).padding(.top, 6)
        HStack(spacing: Spacing.xs) {
          PlayButton(playing: playing, action: toggle).disabled(!canPlay)
          if let mode { TranscriptModePicker(mode: mode) }
        }
        .padding(.top, Spacing.s)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// The day it came out and how long it runs.
  private var facts: String {
    var parts: [String] = []
    if let published = item.published { parts.append(published.date.formatted(date: .abbreviated, time: .omitted)) }
    if length > .zero {
      parts.append(length.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
    }
    return parts.joined(separator: "  ·  ")
  }
}

/// Plays or pauses the episode: a filled capsule, its symbol turning as it changes.
private struct PlayButton: View {
  let playing: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: playing ? Symbols.pause : Symbols.play)
          .font(.system(size: 12, weight: .bold))
          .contentTransition(.symbolEffect(.replace))
        Text(playing ? .loci("player.pause") : .loci("player.play"))
      }
      .font(Typography.buttonStrong)
      .foregroundStyle(Palette.canvas)
      .padding(.horizontal, Spacing.m)
      .frame(height: Size.episodePlay)
      .background(Capsule().fill(Palette.ink))
      .contentShape(Capsule())
    }
    .buttonStyle(PressStyle())
  }
}

/// Original, both, or the translation, for the words of the transcript.
private struct TranscriptModePicker: View {
  @Binding var mode: SubtitleMode

  var body: some View {
    Menu {
      Picker(selection: $mode) {
        ForEach(SubtitleMode.allCases, id: \.self) { mode in Text(mode.name).tag(mode) }
      } label: {
        EmptyView()
      }
      .pickerStyle(.inline)
    } label: {
      Label {
        Text(mode.name)
      } icon: {
        Image(systemName: Symbols.translate)
      }
    }
    .menuStyle(.button)
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .controlSize(.large)
    .fixedSize()
  }
}

/// The episode's chapters, the one playing in ink with an amber mark; a click plays from one.
struct EpisodeChapters: View {
  let chapters: [Outline.Chapter]
  let current: Outline.Chapter?
  /// The sound is playing, so the chapter's mark moves.
  let moving: Bool
  let play: (Duration) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(chapters, id: \.start) { chapter in
        ChapterRow(chapter: chapter, current: chapter == current, moving: moving) { play(chapter.start) }
      }
    }
  }
}

private struct ChapterRow: View {
  let chapter: Outline.Chapter
  let current: Bool
  let moving: Bool
  let action: () -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
        Text(verbatim: MediaTime.text(chapter.start))
          .font(Typography.mono)
          .foregroundStyle(current ? Palette.accentInk : Palette.inkFaint)
          .frame(width: Size.timeColumn + Spacing.s, alignment: .leading)
        Text(verbatim: chapter.title)
          .font(current ? Typography.bodyEmphasis : Typography.body)
          .foregroundStyle(current ? Palette.ink : Palette.inkMuted)
        Spacer(minLength: 0)
        if current {
          Image(systemName: Symbols.chapterPlaying).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.accent)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: moving && !reduceMotion)
        }
      }
      .padding(.horizontal, Spacing.xs)
      .frame(minHeight: 30)
      .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fill : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
