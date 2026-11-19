import LociModel
import SwiftUI

struct ActivityDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns

  nonisolated static let size = CGSize(width: 18, height: 14)

  var body: some View {
    let still = reduceMotion || standIns?.conversationAt != nil
    TimelineView(.animation(paused: still)) { timeline in
      Canvas { context, _ in
        for spot in Self.spots(at: still ? 0 : timeline.date.timeIntervalSinceReferenceDate) {
          context.fill(Path(ellipseIn: spot), with: .color(Palette.accent))
        }
      }
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .accessibilityHidden(true)
  }

  nonisolated static func spots(at time: TimeInterval) -> [CGRect] {
    let turn = (time / 1.8).truncatingRemainder(dividingBy: 1) * 2 * Double.pi
    return [3.2, 3.8, 2.8].enumerated().map { index, diameter in
      let offset = Double(index) * 2.1
      let angle = turn + offset + 0.25 * sin(2 * turn + offset)
      let spread = 0.8 + 0.2 * cos(turn + 2 * offset)
      let x = size.width / 2 + cos(angle) * 6 * spread
      let y = size.height / 2 + sin(angle) * 4 * spread
      return CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)
    }
  }
}

struct ActivityElapsed: View {
  let since: Timestamp
  @Environment(\.standIns) private var standIns

  var body: some View {
    Group {
      if let now = standIns?.conversationAt {
        label(at: now)
      } else {
        TimelineView(.periodic(from: .now, by: 1)) { label(at: $0.date) }
      }
    }
    .font(.system(size: 11).monospaced())
    .foregroundStyle(Palette.inkMuted)
    .fixedSize()
  }

  private func label(at now: Date) -> Text {
    let seconds = Self.wholeSeconds(since: since.date, at: now)
    return Text(verbatim: StepsCard.duration(.seconds(seconds), fractional: false))
  }

  nonisolated static func wholeSeconds(since start: Date, at now: Date) -> Int {
    Int(max(0, now.timeIntervalSince(start)))
  }
}
