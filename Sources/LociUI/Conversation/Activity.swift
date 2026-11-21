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
