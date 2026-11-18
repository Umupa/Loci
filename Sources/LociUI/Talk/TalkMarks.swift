import SwiftUI

/// Where a new day or a new sitting begins: `今天 09:12`.
struct DayDivider: View {
  let label: Text

  var body: some View {
    label
      .font(.system(size: 11.5).monospaced())
      .foregroundStyle(Palette.inkFaint)
      .frame(maxWidth: .infinity)
      .padding(.top, 22)
      .padding(.bottom, 14)
  }
}

/// Something that happened in the world Loci and the person share, such as finishing an item: a thin
/// capsule with the item's cover, what happened, and when.
struct EventPill<Cover: View>: View {
  let words: Text
  let time: Text
  @ViewBuilder let cover: () -> Cover

  var body: some View {
    CappedWidth(share: Self.widest) { pill }
      .frame(maxWidth: .infinity)
      .padding(.top, Spacing.m)
      .padding(.bottom, 10)
  }

  /// The most of the column a capsule takes; a long title is cut short.
  private static var widest: CGFloat { 0.7 }

  private var pill: some View {
    HStack(spacing: 9) {
      cover()
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
      words.lineLimit(1).truncationMode(.tail)
      time.font(.system(size: 11).monospaced()).foregroundStyle(Palette.inkFaint).fixedSize()
    }
    .font(.system(size: 12.5))
    .foregroundStyle(Palette.inkMuted)
    .padding(.vertical, 5)
    .padding(.leading, 5)
    .padding(.trailing, Spacing.s)
    .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
  }
}

/// Three dots rising in turn in Loci's bubble while it has not said anything yet.
struct TypingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      HStack(spacing: Spacing.xxs) {
        ForEach(0..<3, id: \.self) { dot in
          let lift = Self.lift(at: time - Double(dot) * 0.15)
          Circle()
            .fill(Palette.inkFaint)
            .frame(width: 6, height: 6)
            .opacity(0.5 + 0.5 * lift)
            .offset(y: -3 * lift)
        }
      }
      .padding(.vertical, 5)
      .padding(.horizontal, 2)
    }
    .accessibilityHidden(true)
  }

  /// How high a dot is, from 0 to 1: up and back in the first 60% of each 1.2-second beat, then still.
  static func lift(at time: Double) -> Double {
    let beat = (time / 1.2).truncatingRemainder(dividingBy: 1)
    let phase = beat < 0 ? beat + 1 : beat
    guard phase < 0.6 else { return 0 }
    return phase < 0.3 ? phase / 0.3 : (0.6 - phase) / 0.3
  }
}
