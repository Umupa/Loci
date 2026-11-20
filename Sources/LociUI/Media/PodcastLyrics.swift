import AppKit
import LociModel
import SwiftUI

/// A podcast with its subtitles on: the cover and show on the left, and on the right the sentence playing in
/// large serif letters that fill in as it is spoken, the ones around it faded, each with its translation
/// under it, rolling up as the talk goes on. Behind it all, a slow glow in the cover's colors.
struct PodcastLyrics: View {
  @Environment(\.covers) private var covers
  let model: StageModel
  let transcript: ReadableTranscript

  var body: some View {
    let playing = TranscriptFollow.playing(in: transcript.segments, at: model.player.time) ?? 0
    GeometryReader { frame in
      let layout = LyricsLayout(width: frame.size.width)
      ZStack {
        CoverGlow(colors: CoverColors.of(covers?.image(of: model.item.id)))
        VStack(spacing: 0) {
          HStack(alignment: .center, spacing: layout.gap) {
            VStack(alignment: .leading, spacing: 0) {
              SquareCover(item: model.item, corner: layout.cover * 0.07)
                .frame(width: layout.cover, height: layout.cover)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 24)
              Text(serif: model.item.title, Serif.Face(size: layout.cover < 220 ? 16 : 20, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
              Text(verbatim: show)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, 4)
            }
            .frame(width: layout.cover)
            lines(playing: playing, layout: layout)
          }
          .padding(.horizontal, layout.margin)
          .frame(maxHeight: .infinity)
          controls.padding(.horizontal, layout.margin).padding(.bottom, 30)
        }
      }
    }
    .clipped()
  }

  private var show: String {
    [
      model.item.site ?? model.item.authors.first,
      model.timeline.length > .zero ? MediaTime.text(model.timeline.length) : nil,
    ]
    .compactMap { $0 }.joined(separator: " · ")
  }

  private func lines(playing: Int, layout: LyricsLayout) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(transcript.segments.indices, id: \.self) { index in
            line(index, now: index == playing, layout: layout).id(index)
          }
        }
        .padding(.vertical, 200)
      }
      .scrollIndicators(.never)
      .mask(
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.18),
            .init(color: .black, location: 0.82),
            .init(color: .clear, location: 1),
          ], startPoint: .top, endPoint: .bottom)
      )
      .onAppear { proxy.scrollTo(playing, anchor: .center) }
      .onChange(of: playing) { _, now in
        withAnimation(.spring(duration: 0.8, bounce: 0.05)) { proxy.scrollTo(now, anchor: .center) }
      }
    }
  }

  private func line(_ index: Int, now: Bool, layout: LyricsLayout) -> some View {
    let segment = transcript.segments[index]
    let filled = now ? LyricFill.characters(of: segment, at: model.player.time) : 0
    let size = now ? layout.current : layout.around
    return VStack(alignment: .leading, spacing: 5) {
      Text(LyricFill.text(segment.text, filled: filled, now: now))
        .font(Font(NSFont.serif(ofSize: size, weight: .semibold)))
        .lineSpacing(size * 0.12)
        .lineLimit(now ? 3 : 2)
        .minimumScaleFactor(now ? 0.75 : 1)
      if let translated = transcript.translated(index) {
        Text(verbatim: translated).font(.system(size: layout.translation)).foregroundStyle(Palette.inkMuted)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 10)
    .opacity(now ? 1 : 0.3)
    .blur(radius: now ? 0 : 0.8)
    .animation(.easeOut(duration: 0.5), value: now)
    .contentShape(Rectangle())
    .onTapGesture { model.player.seek(to: segment.start) }
  }

  private var controls: some View {
    VStack(spacing: 10) {
      Scrubber(
        timeline: model.timeline, time: model.player.time, onlyKeyPoints: model.onlyKeyPoints?.wrappedValue == true,
        seek: model.player.seek)
      HStack(spacing: 14) {
        Text(verbatim: MediaTime.text(model.player.time)).font(Typography.clock).foregroundStyle(Palette.inkMuted)
        Spacer(minLength: 0)
        if let only = model.onlyKeyPoints { OnlyKeyPointsPill(on: only, compact: true) }
        SpeedChip(player: model.player)
        RoundIconButton(symbol: Symbols.back5, title: .loci("player.back"), symbolSize: 19) {
          model.player.skip(by: .seconds(-5))
        }
        Button {
          model.player.toggle()
        } label: {
          Image(systemName: model.player.playing ? Symbols.pause : Symbols.play)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.canvas)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Palette.ink).shadow(color: .black.opacity(0.18), radius: 8, y: 6))
        }
        .buttonStyle(PressStyle())
        .disabled(!model.player.canPlay)
        .accessibilityLabel(Text(model.player.playing ? .loci("player.pause") : .loci("player.play")))
        RoundIconButton(symbol: Symbols.forward5, title: .loci("player.forward"), symbolSize: 19) {
          model.player.skip(by: .seconds(5))
        }
        RoundIconButton(symbol: Symbols.subtitles, title: .loci("subtitles.off"), symbolSize: 15, on: true) {
          model.subtitlesShown = false
        }
        Spacer(minLength: 0)
        Text(verbatim: MediaTime.remaining(at: model.player.time, of: model.timeline.length))
          .font(Typography.clock).foregroundStyle(Palette.inkMuted)
      }
    }
  }
}

/// How the large words fit the stage: a smaller cover and smaller letters when the stage is narrow, as it is
/// with the panel beside it, so the sentence playing takes at most about three lines.
struct LyricsLayout: Equatable {
  let cover: CGFloat
  let gap: CGFloat
  let margin: CGFloat
  /// The sentence playing.
  let current: CGFloat
  /// The sentences before and after it, a size smaller.
  let around: CGFloat
  let translation: CGFloat

  init(width: CGFloat) {
    let narrow = width < 900
    cover = narrow ? 168 : 260
    gap = narrow ? 36 : 56
    margin = narrow ? 36 : 56
    let column = max(width - margin * 2 - cover - gap, 160)
    current = min(max(column / 17, 18), 28)
    around = (current * 0.78).rounded()
    translation = min(max(current * 0.58, 13), 16)
  }
}

/// How much of a sentence is filled in at a moment, spread evenly over the time it is spoken.
enum LyricFill {
  static func characters(of segment: Transcript.Segment, at time: Duration) -> Int {
    let length = (segment.end - segment.start).roundedMilliseconds
    guard length > 0 else { return segment.text.count }
    let share = Double((time - segment.start).roundedMilliseconds) / Double(length)
    return Int((min(max(share, 0), 1) * Double(segment.text.count)).rounded())
  }

  /// The sentence with its first `filled` characters in full ink and the rest faint.
  static func text(_ sentence: String, filled: Int, now: Bool) -> AttributedString {
    var text = AttributedString(sentence)
    text.foregroundColor = now ? Palette.ink.opacity(0.4) : Palette.ink
    guard now, filled > 0 else { return text }
    let end = text.index(text.startIndex, offsetByCharacters: min(filled, sentence.count))
    text[text.startIndex..<end].foregroundColor = Palette.ink
    return text
  }
}

/// Two colors drawn from a cover, for the glow behind a podcast; amber and rust until the cover is there.
struct CoverColors: Equatable {
  let first: Color
  let second: Color

  static let standard = CoverColors(
    first: Color(nsColor: NSColor(rgb: 0xFFAA50)), second: Color(nsColor: NSColor(rgb: 0xC85028)))

  /// The average color of the cover's top left and its bottom right.
  static func of(_ image: NSImage?) -> CoverColors {
    guard let image, let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { return standard }
    context.cgContext.interpolationQuality = .medium
    context.cgContext.draw(picture, in: CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let top = bitmap.colorAt(x: 0, y: 0), let bottom = bitmap.colorAt(x: 1, y: 1) else { return standard }
    return CoverColors(first: Color(nsColor: top), second: Color(nsColor: bottom))
  }
}

/// A soft light in two colors, drifting slowly behind the page.
private struct CoverGlow: View {
  let colors: CoverColors

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
      let phase = sin(context.date.timeIntervalSinceReferenceDate / 14 * .pi)
      GeometryReader { frame in
        let size = frame.size
        let reach = max(size.width, size.height) * 0.55
        ZStack {
          RadialGradient(
            colors: [colors.first.opacity(0.34), colors.first.opacity(0)],
            center: UnitPoint(x: 0.3 + 0.04 * phase, y: 0.3 - 0.03 * phase), startRadius: 0, endRadius: reach)
          RadialGradient(
            colors: [colors.second.opacity(0.26), colors.second.opacity(0)],
            center: UnitPoint(x: 0.75 - 0.03 * phase, y: 0.62 + 0.03 * phase), startRadius: 0, endRadius: reach)
        }
        .scaleEffect(1 + 0.03 * phase)
        .blur(radius: 40)
      }
    }
    .allowsHitTesting(false)
  }
}
