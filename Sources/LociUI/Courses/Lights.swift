import SwiftUI

/// Where a light that keeps running is in its cycle, from 0 to 1: the time now, held at `held` for a snapshot,
/// and `nil` while the person has asked for less motion, so the light shows still.
struct LightClock<Content: View>: View {
  @Environment(\.standIns) private var standIns
  @Environment(\.reducesMotion) private var reduceMotion
  let period: Double
  var held = 0.4
  @ViewBuilder let content: (Double?) -> Content

  var body: some View {
    TimelineView(.animation(paused: standIns != nil || reduceMotion)) { context in
      content(phase(at: context.date))
    }
  }

  private func phase(at date: Date) -> Double? {
    if reduceMotion { return nil }
    if standIns != nil { return held }
    return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
  }
}

/// Words being written: faint, with a band of full ink crossing them from right to left again and again.
struct ShimmerText: View {
  let text: Text
  var ink = Palette.ink
  var held = 0.45

  var body: some View {
    LightClock(period: Motion.shimmerPeriod, held: held) { phase in
      if let phase {
        let at = 1.2 - phase * 1.4
        text.foregroundStyle(
          LinearGradient(
            stops: [
              .init(color: ink.opacity(0.3), location: 0),
              .init(color: ink.opacity(0.3), location: clamp(at - 0.16)),
              .init(color: ink.opacity(0.95), location: clamp(at)),
              .init(color: ink.opacity(0.3), location: clamp(at + 0.16)),
              .init(color: ink.opacity(0.3), location: 1),
            ], startPoint: .leading, endPoint: .trailing))
      } else {
        text.foregroundStyle(ink.opacity(0.55))
      }
    }
  }

  private func clamp(_ value: Double) -> Double { min(max(value, 0.0001), 0.9999) }
}

/// Gold leaf catching the light: a soft bright band sweeping across a cover while its course is being written.
struct FoilSweep: View {
  var held = 0.35

  var body: some View {
    LightClock(period: 2.6, held: held) { phase in
      if let phase {
        GeometryReader { frame in
          let width = frame.size.width
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0.35), .init(color: Palette.Glow.gold.opacity(0.26), location: 0.48),
              .init(color: .clear, location: 0.6),
            ], startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8)
          )
          .frame(width: width * 2.6)
          .offset(x: width * (0.9 - phase * 2.6))
          .blendMode(.plusLighter)
        }
      }
    }
    .allowsHitTesting(false)
  }
}

/// An amber bead with a ring that swells and fades, for the lesson being written.
struct PulsingBead: View {
  var size = Size.bead
  var filled = true

  var body: some View {
    LightClock(period: 1.4, held: 0.3) { phase in
      let swell = phase.map { sin($0 * .pi) } ?? 0.4
      Circle()
        .fill(filled ? Palette.accent : Palette.accent.opacity(0.25))
        .overlay { if !filled { Circle().strokeBorder(Palette.accent, lineWidth: 1) } }
        .frame(width: size, height: size)
        .background {
          Circle().fill(Palette.accent.opacity(0.22 * (1 - swell * 0.8)))
            .frame(width: size + 8 + swell * 6, height: size + 8 + swell * 6)
        }
    }
    .frame(width: size, height: size)
  }
}
