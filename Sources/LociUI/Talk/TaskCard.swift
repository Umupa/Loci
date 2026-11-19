import SwiftUI

/// Work going on for the person, step by step: a title, how far along, and each step done, going or
/// still to come. Once finished it steps back.
struct TaskCard: View {
  enum StepState { case done, now, later }

  let title: Text
  /// From 0 to 1.
  let progress: Double
  let steps: [(words: Text, state: StepState)]
  /// Why the work stopped, under the steps.
  var problem: Text?
  var indent = TalkScale.main.indent

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Spacing.xs) {
        title.font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
        Spacer(minLength: Spacing.xs)
        Text(progress, format: .percent.precision(.fractionLength(0)))
          .font(.system(size: 11).monospaced())
          .foregroundStyle(Palette.inkMuted)
      }
      bar.padding(.top, 9).padding(.bottom, Spacing.xs)
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        ForEach(steps.indices, id: \.self) { index in
          let step = steps[index]
          HStack(spacing: Spacing.xs) {
            BreathingDot(
              color: step.state == .later ? Tones.fillStrong : Tones.accent, size: 6, breathing: step.state == .now,
              period: 1)
            step.words.foregroundStyle(step.state == .done ? Palette.ink : Palette.inkMuted)
          }
        }
      }
      .font(.system(size: 12.5))
      if let problem {
        problem.font(.system(size: 12.5)).foregroundStyle(Palette.accentInk).padding(.top, 6)
      }
    }
    .padding(.vertical, 11)
    .padding(.horizontal, 13)
    .frame(width: 360, alignment: .leading)
    .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(
        Palette.line, lineWidth: Size.hairline)
    )
    .opacity(finished ? 0.7 : 1)
    .padding(.leading, indent)
    .padding(.top, 6)
    .padding(.bottom, Spacing.xxs)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var finished: Bool { progress >= 1 }

  private var bar: some View {
    Capsule()
      .fill(Palette.fillStrong)
      .frame(height: 3)
      .overlay(alignment: .leading) {
        GeometryReader { track in
          Capsule().fill(Palette.accent).frame(width: track.size.width * min(max(progress, 0), 1))
        }
      }
      .animation(Motion.arrive, value: progress)
  }
}
