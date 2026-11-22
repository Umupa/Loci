import SwiftUI

/// The two ends of an answer's flight: the answer chosen in the conversation, and the line of the title page it
/// is written on.
enum FlightEnd: Hashable {
  case answer(Int)
  case line(Int)
}

/// Where each end of a flight is laid out.
struct FlightEnds: PreferenceKey {
  static let defaultValue: [FlightEnd: Anchor<CGRect>] = [:]

  static func reduce(value: inout [FlightEnd: Anchor<CGRect>], nextValue: () -> [FlightEnd: Anchor<CGRect>]) {
    value.merge(nextValue()) { $1 }
  }
}

/// One chosen answer on its way to the title page.
struct Flight: Identifiable, Equatable {
  let id = UUID()
  let from: CGRect
  let to: CGRect
  /// The answer's title, carried along.
  let words: String
  /// Seconds after the first answer of the same pick, so several fly one after another.
  var delay = 0.0
}

/// A chosen answer lifting off as a card, arcing up and over to its line on the title page, and shrinking into
/// it. `progress` runs from 0, where the answer was, to 1, gone into the line.
struct FlyingAnswer: View, Animatable {
  let flight: Flight
  var progress: Double

  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let at = position
    let shrink = 1 - 0.82 * progress
    RoundedRectangle(cornerRadius: Radius.answer, style: .continuous)
      .fill(Palette.bubbleMine)
      .overlay(alignment: .leading) {
        Text(verbatim: flight.words)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Palette.ink)
          .lineLimit(1)
          .fixedSize()
          .scaleEffect(1 - 0.5 * progress, anchor: .leading)
          .padding(.leading, 14 * shrink)
          .opacity(1 - progress)
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.answer, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: Radius.answer, style: .continuous)
          .strokeBorder(Palette.accent.opacity(0.5 * (1 - progress)), lineWidth: 1)
      }
      .frame(width: flight.from.width * shrink, height: flight.from.height * (1 - 0.7 * progress))
      .shadow(color: Palette.warmShadow.opacity(0.35), radius: 17, y: 14)
      .opacity(progress < 0.55 ? 1 : max(0, 1 - (progress - 0.55) / 0.45))
      .position(at)
      .allowsHitTesting(false)
  }

  /// Along a curve from the answer's center, rising 70 points over the straight way, to the start of the line.
  private var position: CGPoint {
    let start = CGPoint(x: flight.from.midX, y: flight.from.midY)
    let end = CGPoint(x: flight.to.minX + flight.from.width * 0.09, y: flight.to.minY + 10)
    let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 70)
    let t = progress
    let u = 1 - t
    return CGPoint(
      x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
      y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
  }
}

/// A flight that sets off as soon as it shows.
struct LaunchedFlight: View {
  @Environment(\.reducesMotion) private var reduceMotion
  let flight: Flight
  let landed: () -> Void
  @State private var progress = 0.0

  var body: some View {
    FlyingAnswer(flight: flight, progress: progress)
      .opacity(reduceMotion ? 0 : 1)
      .task {
        withAnimation(Motion.fly.delay(flight.delay)) { progress = 1 }
        try? await Task.sleep(for: .seconds(0.8 + flight.delay))
        landed()
      }
  }
}
