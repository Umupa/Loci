import LociModel
import SwiftUI

/// Where a value stands in its history: a ruler marked where it is, the lowest and highest at its ends.
struct PanelRulerView: View {
  let ruler: PanelRuler
  @Environment(\.panelData) private var data
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var shown = false

  var body: some View {
    let share = data.number(ruler.share)
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .firstTextBaseline) {
        Text(verbatim: ruler.label).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted).lineLimit(1)
        Spacer(minLength: Spacing.xs)
        Text(
          joining: Text(verbatim: PanelFigures.number(data.number(ruler.value), style: ruler.style))
            .fontWeight(.semibold).foregroundStyle(Palette.ink),
          Text(verbatim: share.map { " · \(PanelFigures.plain($0 * 100, digits: 0))%" } ?? "")
            .foregroundStyle(Palette.inkMuted)
        )
        .font(.system(size: 12.5))
      }
      .monospacedDigit()
      GeometryReader { track in
        ZStack(alignment: .leading) {
          Capsule().fill(
            LinearGradient(
              stops: [
                .init(color: Palette.fall.opacity(0.14), location: 0), .init(color: Palette.fill, location: 0.45),
                .init(color: Palette.fill, location: 0.55), .init(color: Palette.rise.opacity(0.14), location: 1),
              ], startPoint: .leading, endPoint: .trailing))
          ForEach([0.2, 0.4, 0.6, 0.8], id: \.self) { tick in
            Rectangle().fill(Palette.lineStrong).frame(width: 1, height: 4).offset(x: track.size.width * tick)
          }
          if let share {
            Circle().fill(Palette.surface)
              .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 3))
              .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
              .frame(width: 16, height: 16)
              .offset(x: track.size.width * (shown ? min(max(share, 0), 1) : 0) - 8)
          }
        }
        .frame(height: 16)
      }
      .frame(height: 16)
      HStack {
        Text(verbatim: PanelFigures.number(data.number(ruler.low), style: ruler.style))
        Spacer()
        Text(verbatim: PanelFigures.number(data.number(ruler.high), style: ruler.style))
      }
      .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Palette.inkFaint)
    }
    .onAppear {
      withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.9, 0.3, 1, duration: 1.1)) { shown = true }
    }
  }
}

/// A bar cut into zones, one line for each value, with the stops written under the bars.
struct PanelZonesView: View {
  let zones: PanelZones
  @Environment(\.panelData) private var data
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var shown = false
  private static let name: CGFloat = 64
  private static let value: CGFloat = 60

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(zones.rows.enumerated()), id: \.offset) { _, row in
        line(row).padding(.vertical, 7)
      }
      HStack(spacing: 10) {
        Color.clear.frame(width: Self.name, height: 1)
        GeometryReader { scale in
          ForEach(Array(zones.stops.enumerated()), id: \.offset) { _, stop in
            Text(verbatim: PanelFigures.number(stop, style: zones.style, defaultDigits: 0))
              .fixedSize()
              .position(x: scale.size.width * position(of: stop), y: 7)
          }
        }
        .frame(height: 14)
        Color.clear.frame(width: Self.value, height: 1)
      }
      .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Palette.inkFaint)
    }
    .onAppear {
      withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.9, 0.3, 1, duration: 1.1)) { shown = true }
    }
  }

  private func line(_ row: PanelZoneRow) -> some View {
    let value = data.number(row.value)
    let tone = tone(of: value)
    return HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: row.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
        if let note = row.note { Text(verbatim: note).font(.system(size: 11)).foregroundStyle(Palette.inkFaint) }
      }
      .lineLimit(1)
      .frame(width: Self.name, alignment: .leading)
      GeometryReader { bar in
        ZStack(alignment: .leading) {
          HStack(spacing: 0) {
            ForEach(Array(zip(zones.stops, zones.stops.dropFirst()).enumerated()), id: \.offset) { index, span in
              Rectangle().fill(fill(zone: index))
                .frame(width: bar.size.width * (position(of: span.1) - position(of: span.0)))
            }
          }
          .clipShape(Capsule())
          if let value {
            Circle().fill(Palette.surface)
              .overlay(Circle().strokeBorder(tone, lineWidth: 2.5))
              .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
              .frame(width: 13, height: 13)
              .offset(x: bar.size.width * (shown ? position(of: value) : 0) - 6.5)
          }
        }
        .frame(height: 13)
      }
      .frame(height: 13)
      Text(verbatim: PanelFigures.number(value, style: zones.style))
        .font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(tone)
        .contentTransition(.numericText())
        .frame(width: Self.value, alignment: .trailing)
    }
    .animation(reduceMotion ? nil : .default, value: value)
  }

  private func position(of value: Double) -> Double {
    panelShare(value, from: zones.stops.first ?? 0, to: zones.stops.last ?? 1)
  }

  /// The first zone is green, the last red, those between plain.
  private func fill(zone: Int) -> Color {
    if zone == 0 { return Palette.fall.opacity(0.14) }
    if zone == zones.stops.count - 2 { return Palette.rise.opacity(0.14) }
    return Palette.fill
  }

  private func tone(of value: Double?) -> Color {
    guard let value, let first = zones.stops.dropFirst().first, let last = zones.stops.dropLast().last else {
      return Palette.ink
    }
    if value < first { return Palette.fall }
    if value >= last { return Palette.rise }
    return Palette.ink
  }
}
