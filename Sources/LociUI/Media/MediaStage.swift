import AVKit
import LociModel
import SwiftUI

/// What the stage of a video or audio item needs from the page around it.
struct StageModel {
  let item: Item
  let player: Player
  let timeline: Timeline
  let transcript: ReadableTranscript?
  @Binding var subtitles: SubtitleMode
  @Binding var subtitlesShown: Bool
  @Binding var menuOpen: Bool
  @Binding var style: SubtitleStyle
  /// `nil` until there are key points to play alone.
  let onlyKeyPoints: Binding<Bool>?
  /// How subtitles look is open beside the stage.
  let styling: Bool
  let openStyle: () -> Void
}

/// A video's page: the picture, the progress bar, the controls, and the title with where it comes from.
struct VideoStage: View {
  let model: StageModel

  var body: some View {
    GeometryReader { frame in
      let width = max(frame.size.width - 52, 0)
      VStack(alignment: .leading, spacing: 0) {
        picture.frame(width: width, height: width * 9 / 16)
        Scrubber(
          timeline: model.timeline, time: model.player.time, onlyKeyPoints: model.onlyKeyPoints?.wrappedValue == true,
          seek: model.player.seek
        )
        .padding(.horizontal, 2)
        .padding(.top, Spacing.m)
        controls(compact: width < Self.compactWidth).padding(.top, 6)
        Text(serif: model.item.title, Typography.mediaTitle)
          .foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 2)
          .padding(.top, 18)
          .padding(.bottom, 7)
        ItemMeta(item: model.item).padding(.horizontal, 2)
        WhyLine(item: model.item).padding(.horizontal, 2).padding(.top, 10)
      }
      .frame(width: width)
      .padding(.top, 30)
      .padding(.bottom, 40)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var picture: some View {
    Cover(item: model.item, corner: Radius.cover)
      .overlay {
        if !model.player.soundOnly { VideoSurface(player: model.player.engine) }
      }
      .overlay(alignment: .bottom) {
        if model.subtitlesShown, let lines = currentLines {
          SubtitleOverlay(lines: lines, style: model.style) { model.style.lift = $0 }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.cover, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Radius.cover, style: .continuous)
          .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
      )
      .shadow(color: Color(nsColor: NSColor(rgb: 0x281905)).opacity(0.18), radius: 25, y: 18)
      .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
  }

  private var currentLines: [SubtitleLine]? {
    guard let transcript = model.transcript,
      let index = TranscriptFollow.playing(in: transcript.segments, at: model.player.time),
      transcript.segments[index].end >= model.player.time
    else { return nil }
    return transcript.lines(index, mode: model.subtitles, order: model.style.order)
  }

  /// Below this the picture is too narrow for every control; skipping, the chapter and the speed fold away
  /// and the subtitle chip keeps only its symbol.
  static let compactWidth: CGFloat = 520

  private func controls(compact: Bool) -> some View {
    HStack(spacing: Spacing.xxs) {
      RoundIconButton(
        symbol: model.player.playing ? Symbols.pause : Symbols.play,
        title: model.player.playing ? .loci("player.pause") : .loci("player.play"), symbolSize: 18
      ) { model.player.toggle() }
      .disabled(!model.player.canPlay)
      if !compact {
        RoundIconButton(symbol: Symbols.back5, title: .loci("player.back")) { model.player.skip(by: .seconds(-5)) }
        RoundIconButton(symbol: Symbols.forward5, title: .loci("player.forward")) {
          model.player.skip(by: .seconds(5))
        }
      }
      Text(verbatim: MediaTime.progress(at: model.player.time, of: model.timeline.length))
        .font(Typography.clock)
        .foregroundStyle(Palette.inkMuted)
        .padding(.leading, Spacing.xs)
        .fixedSize()
      if !compact, let chapter = model.timeline.chapter(at: model.player.time) {
        Text(verbatim: chapter.title)
          .font(.system(size: 12))
          .foregroundStyle(Palette.inkFaint)
          .lineLimit(1)
          .padding(.leading, Spacing.xs)
      }
      Spacer(minLength: Spacing.xs)
      if let only = model.onlyKeyPoints { OnlyKeyPointsPill(on: only, compact: compact) }
      if !compact { SpeedChip(player: model.player) }
      SubtitleChip(model: model, symbol: true, named: !compact)
      RoundIconButton(
        symbol: Symbols.subtitleStyle, title: .loci("caption.title"), symbolSize: 14, on: model.styling,
        action: model.openStyle)
      RoundIconButton(symbol: Symbols.fullScreen, title: .loci("player.fullScreen"), symbolSize: 15) {
        NSApp.keyWindow?.toggleFullScreen(nil)
      }
    }
  }
}

/// Plays only the key points, one after another; amber while on.
struct OnlyKeyPointsPill: View {
  @Binding var on: Bool
  var compact = false
  @State private var hovering = false

  var body: some View {
    Button {
      withAnimation(Motion.quick) { on.toggle() }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: Symbols.keyPoints)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(on ? Palette.accent : Palette.inkMuted)
        if !compact { Text(.loci("keypoints.only")) }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(on ? Palette.accentInk : Palette.inkMuted)
      .padding(.horizontal, 10)
      .frame(height: 26)
      .background(Capsule().fill(on ? Palette.tint : hovering ? Palette.fill : .clear))
      .overlay(Capsule().strokeBorder(on ? Palette.accent.opacity(0.45) : Palette.lineStrong, lineWidth: 1))
      .contentShape(Capsule())
      .fixedSize()
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(.loci("keypoints.only")))
    .accessibilityLabel(Text(.loci("keypoints.only")))
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// The speed, stepping up on each click and back to the start after the fastest.
struct SpeedChip: View {
  let player: Player

  var body: some View {
    Chip(action: {
      player.set(player.speed == .double ? .half : player.speed.faster)
    }) {
      Text(verbatim: player.speed.label).font(.system(size: 12, weight: .medium).monospaced())
    }
    .help(Text(.loci("player.speed")))
  }
}

/// Which subtitles show, with a menu of the three ways and none.
struct SubtitleChip: View {
  let model: StageModel
  let symbol: Bool
  /// Says which subtitles show; a narrow stage leaves only the symbol.
  var named = true

  var body: some View {
    Chip(open: model.menuOpen, action: { withAnimation(Motion.quick) { model.menuOpen.toggle() } }) {
      if symbol { Image(systemName: Symbols.subtitles).font(.system(size: 13)) }
      if named || !symbol { Text(model.subtitlesShown || !symbol ? shown.name : .loci("subtitles.off")) }
      ChipChevron()
    }
    .overlay(alignment: .bottomTrailing) {
      if model.menuOpen {
        SubtitleMenu(model: model)
          .offset(y: -36)
          .alignmentGuide(.bottom) { $0[.bottom] }
          .transition(.scale(scale: 0.96, anchor: .bottom).combined(with: .opacity))
      }
    }
    .zIndex(1)
  }
}

extension SubtitleChip {
  /// Without a translation there is only the original to show.
  fileprivate var shown: SubtitleMode {
    model.transcript?.translation == nil ? .original : model.subtitles
  }
}

/// Original, side by side, translation, or no subtitles over the picture.
private struct SubtitleMenu: View {
  let model: StageModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(SubtitleMode.allCases, id: \.self) { mode in
        entry(mode.name, on: model.subtitlesShown && model.subtitles == mode) {
          model.subtitles = mode
          model.subtitlesShown = true
        }
      }
      Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
      entry(.loci("subtitles.off"), on: !model.subtitlesShown) { model.subtitlesShown = false }
    }
    .padding(5)
    .frame(width: 168)
    .background(
      RoundedRectangle(cornerRadius: Radius.group, style: .continuous).fill(Palette.floating)
        .shadow(color: .black.opacity(0.24), radius: 25, y: 18)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.group, style: .continuous).strokeBorder(
        Palette.lineStrong, lineWidth: Size.hairline)
    )
    .fixedSize()
  }

  private func entry(_ title: LocalizedStringResource, on: Bool, choose: @escaping () -> Void) -> some View {
    MenuEntry(title: title, on: on) {
      choose()
      withAnimation(Motion.quick) { model.menuOpen = false }
    }
  }
}

/// A row of a small menu: a check when on, amber under the pointer.
private struct MenuEntry: View {
  let title: LocalizedStringResource
  let on: Bool
  let choose: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      HStack(spacing: Spacing.xs) {
        Text(verbatim: on ? "✓" : "").font(.system(size: 12)).foregroundStyle(
          hovering ? Palette.onAccent : Palette.accent
        )
        .frame(width: 12)
        Text(title).font(.system(size: 13)).foregroundStyle(hovering ? Palette.onAccent : Palette.ink)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.xs)
      .frame(height: 26)
      .background(RoundedRectangle(cornerRadius: Radius.thumbnail).fill(hovering ? Palette.accent : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}

/// Under a title: who made it, where it was published, and a link to the original.
struct ItemMeta: View {
  let item: Item

  var body: some View {
    HStack(spacing: 6) {
      Text(verbatim: parts.joined(separator: " · ")).lineLimit(1)
      if let source = item.source {
        Button {
          NSWorkspace.shared.open(source)
        } label: {
          Image(systemName: Symbols.external).font(.system(size: 12)).foregroundStyle(Palette.inkMuted)
        }
        .buttonStyle(.plain)
        .help(Text(.loci("item.openOriginal")))
      }
    }
    .font(.system(size: 11.5).monospaced())
    .foregroundStyle(Palette.inkFaint)
  }

  private var parts: [String] {
    var parts: [String] = []
    if let site = item.site { parts.append(site) }
    parts += item.authors.filter { $0 != item.site }
    if let host = item.source?.host() { parts.append(host.replacing(/^www\./, with: "")) }
    return parts
  }
}

/// The video's frames, drawn by AVKit with no controls of its own.
private struct VideoSurface: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .none
    view.videoGravity = .resizeAspect
    view.player = player
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
  }
}
