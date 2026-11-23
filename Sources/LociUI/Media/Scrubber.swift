import SwiftUI

/// The progress bar under a player: what has played in ink, the key points in amber, a cut between chapters,
/// and a knob to drag. While only the key points play, everything but them fades.
struct Scrubber: View {
  let timeline: Timeline
  let time: Duration
  var onlyKeyPoints = false
  let seek: (Duration) -> Void
  @State private var dragging: Double?

  var body: some View {
    GeometryReader { frame in
      let width = frame.size.width
      let played = dragging ?? timeline.share(time)
      ZStack(alignment: .topLeading) {
        Group {
          Capsule().fill(Palette.fillStrong).frame(height: 4).offset(y: 9)
          UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2)
            .fill(Palette.ink.opacity(0.72))
            .frame(width: width * played, height: 4)
            .offset(y: 9)
        }
        .opacity(onlyKeyPoints ? 0.3 : 1)
        ForEach(Array(timeline.cuts.enumerated()), id: \.offset) { _, cut in
          Rectangle().fill(Palette.canvas).frame(width: 3, height: 6).offset(x: width * cut - 1.5, y: 8)
        }
        ForEach(Array(timeline.keyPoints.enumerated()), id: \.offset) { _, span in
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Palette.accent)
            .frame(width: max(4, width * (span.upperBound - span.lowerBound)), height: 8)
            .background(
              RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.canvas).padding(-2)
            )
            .offset(x: width * span.lowerBound, y: 7)
        }
        Circle()
          .fill(.white)
          .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: Size.hairline))
          .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
          .frame(width: Size.knob, height: Size.knob)
          .offset(x: width * played - Size.knob / 2, y: 5)
      }
      .frame(width: width, height: Size.scrubberHeight, alignment: .topLeading)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { dragging = min(max($0.location.x / max(width, 1), 0), 1) }
          .onEnded { _ in
            if let dragging { seek(timeline.time(at: dragging)) }
            dragging = nil
          })
    }
    .frame(height: Size.scrubberHeight)
    .accessibilityElement()
    .accessibilityLabel(Text(.loci("player.position")))
    .accessibilityValue(Text(verbatim: MediaTime.text(time)))
  }
}

/// A round button with a symbol, as the controls under a player use.
struct RoundIconButton: View {
  let symbol: String
  let title: LocalizedStringResource
  var size: CGFloat = Size.controlButton
  var symbolSize: CGFloat = 17
  /// Shows what it opens is open: a dark glyph on an amber circle.
  var on = false
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: symbolSize, weight: .regular))
        .foregroundStyle(on ? Palette.onAccent : Palette.ink)
        .environment(\.locale, Locale(identifier: "en"))
        .frame(width: size, height: size)
        .background(Circle().fill(on ? Palette.accent : hovering ? Palette.fillStrong : .clear))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }
}

/// A quiet capsule that holds a setting, such as the speed or which subtitles show.
struct Chip<Label: View>: View {
  var open = false
  let action: () -> Void
  @ViewBuilder let label: () -> Label
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) { label() }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(hovering || open ? Palette.ink : Palette.inkMuted)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(hovering || open ? Palette.fillStrong : .clear))
        .contentShape(Capsule())
        .fixedSize()
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
  }
}

/// The small chevron after a chip's words.
struct ChipChevron: View {
  var body: some View {
    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.6)
  }
}
