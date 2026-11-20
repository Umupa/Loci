import SwiftUI

/// Amber light running around the edge of something being worked on: a bright arc that circles once every few
/// seconds, with a soft halo behind it. Snapshots hold it still.
struct AmberGlow: ViewModifier {
  @Environment(\.standIns) private var standIns
  let active: Bool
  let corner: CGFloat
  var width: CGFloat = 2

  func body(content: Content) -> some View {
    content
      .background {
        if active {
          turning { angle in
            GlowShape(corner: corner + width, angle: angle, width: 9)
              .blur(radius: 12)
              .opacity(0.55)
              .padding(-6)
          }
        }
      }
      .overlay {
        if active {
          turning { angle in GlowShape(corner: corner + width, angle: angle, width: width).padding(-width) }
        }
      }
  }

  private func turning(_ draw: @escaping (Angle) -> some View) -> some View {
    TimelineView(.animation(paused: standIns != nil)) { context in
      let turns = standIns != nil ? 0.18 : context.date.timeIntervalSinceReferenceDate / Self.period
      draw(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
    }
    .allowsHitTesting(false)
  }

  /// Seconds for the arc to go once around.
  static let period = 3.4
}

/// One arc of the glow's colors along a rounded rectangle's edge.
private struct GlowShape: View {
  let corner: CGFloat
  let angle: Angle
  let width: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: corner, style: .continuous)
      .strokeBorder(
        AngularGradient(
          stops: [
            .init(color: .clear, location: 0), .init(color: .clear, location: 0.52),
            .init(color: Palette.Glow.amber, location: 0.66), .init(color: Palette.Glow.coral, location: 0.8),
            .init(color: Palette.Glow.gold, location: 0.9), .init(color: Palette.Glow.gold.opacity(0), location: 1),
          ], center: .center, angle: angle),
        lineWidth: width)
  }
}

extension View {
  /// Runs amber light around the edge while `active`.
  func amberGlow(_ active: Bool, corner: CGFloat, width: CGFloat = 2) -> some View {
    modifier(AmberGlow(active: active, corner: corner, width: width))
  }
}
