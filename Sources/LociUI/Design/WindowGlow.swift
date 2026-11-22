import SwiftUI

/// Amber light flowing around all four edges of the window while Loci puts things into the library, with a
/// soft glow inside the edge that slowly breathes. It lets every click through.
struct WindowGlow: View {
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let time = reduceMotion ? 0.6 : context.date.timeIntervalSinceReferenceDate
      let angle = Angle.degrees((time / 4).truncatingRemainder(dividingBy: 1) * 360)
      let breath = 0.32 + 0.12 * cos(time / 2.6 * 2 * .pi)
      let colors = [Palette.Glow.amber, Palette.Glow.coral, Palette.Glow.gold]
      let light = AngularGradient(colors: colors + colors + [colors[0]], center: .center, angle: angle)
      let edge = RoundedRectangle(cornerRadius: Radius.window, style: .continuous)
      ZStack {
        edge.strokeBorder(light, lineWidth: 10).blur(radius: 22).opacity(breath).clipShape(edge)
        edge.strokeBorder(light, lineWidth: 2.5)
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .transition(reduceMotion ? .identity : .opacity.animation(.easeInOut(duration: 0.6)))
  }
}
