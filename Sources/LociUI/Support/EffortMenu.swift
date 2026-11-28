import LociModel
import SwiftUI

/// Thinking effort's mark: an open dial, so it is not read as the clock that marks background work.
struct EffortGauge: View {
  var size: CGFloat = 13

  var body: some View {
    Canvas { canvas, area in
      let center = CGPoint(x: area.width / 2, y: area.height * 0.56)
      let radius = min(area.width, area.height) * 0.41
      var arc = Path()
      arc.addArc(
        center: center, radius: radius,
        startAngle: .degrees(140), endAngle: .degrees(40), clockwise: false)
      var needle = Path()
      needle.move(to: center)
      needle.addLine(to: CGPoint(x: center.x + radius * 0.56, y: center.y - radius * 0.56))
      let style = StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
      canvas.stroke(arc, with: .foreground, style: style)
      canvas.stroke(needle, with: .foreground, style: style)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// Picks how hard an agent thinks. Extra High and Max ripple when chosen or pointed at.
struct EffortMenu: View {
  let provider: Provider
  let effort: ThinkingEffort?
  var width: CGFloat = 210
  let select: (ThinkingEffort?) -> Void
  var onPick: (() -> Void)?
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  @State private var shimmerStart = Date.now

  var body: some View {
    VStack(spacing: 0) {
      row(nil, label: Text(.loci("agents.anyModel")), muted: true)
      Hairline().padding(.vertical, 4).padding(.horizontal, 6)
      ForEach(provider.efforts, id: \.self) { level in
        row(level, label: Text(Agents.effortName(level)), muted: false)
      }
    }
    .padding(4)
    .frame(width: width)
    .onChange(of: effort) { shimmerStart = .now }
  }

  private func row(_ level: ThinkingEffort?, label: Text, muted: Bool) -> some View {
    EffortOptionRow(
      level: level, label: label, chosen: level == effort, muted: muted,
      shimmerStart: shimmerStart, reducesMotion: reduceMotion, frozen: standIns != nil
    ) {
      shimmerStart = .now
      select(level)
      onPick?()
    }
  }
}

private struct EffortOptionRow: View {
  let level: ThinkingEffort?
  let label: Text
  let chosen: Bool
  let muted: Bool
  let shimmerStart: Date
  let reducesMotion: Bool
  let frozen: Bool
  let action: () -> Void
  @State private var hovering = false
  @State private var hoverStart = Date.now

  private var shimmerActive: Bool {
    EffortTileShimmer.color(for: level) != nil && (chosen || hovering) && (!reducesMotion || frozen)
  }

  private var activeStart: Date {
    hovering && hoverStart > shimmerStart ? hoverStart : shimmerStart
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        label
          .font(.system(size: 13, weight: chosen ? .semibold : .regular))
          .foregroundStyle(muted ? Palette.inkMuted : Palette.ink)
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: Symbols.done)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .opacity(chosen ? 1 : 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 32)
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hovering ? Palette.selection : chosen ? Palette.fill : .clear)
          if shimmerActive, let tone = EffortTileShimmer.color(for: level) {
            EffortTileShimmer(color: tone, start: activeStart, frozen: frozen)
              .transition(.opacity)
          }
        }
        .animation(reducesMotion ? nil : Motion.quick, value: shimmerActive)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { over in
      if over { hoverStart = .now }
      hovering = over
    }
  }
}

/// A wave of tiles spreading from the middle of a row, with its edge breathing, played once for about five seconds.
struct EffortTileShimmer: View {
  static let columns = 32
  static let rows = 5

  struct Tile: Hashable {
    let column: Int
    let row: Int
    let distance: Double
    let filled: Bool
  }

  static let grid: [Tile] = {
    let cx = Double(columns - 1) / 2
    let cy = Double(rows - 1) / 2
    return (0..<(columns * rows)).map { index in
      let col = index % columns
      let row = index / columns
      let dx = (Double(col) - cx) / cx
      let dy = (Double(row) - cy) / cy
      let dist = hypot(dx, dy)
      let filled = (index * 73 + index * index * 19 + 23) % 101 < 65
      return Tile(column: col, row: row, distance: dist, filled: filled)
    }
  }()

  static let duration: TimeInterval = 5

  /// The color an effort ripples in; `nil` for the efforts that do not ripple.
  static func color(for effort: ThinkingEffort?) -> Color? {
    switch effort {
    case .xhigh: Palette.effortExtraHigh
    case .max: Palette.effortMax
    default: nil
    }
  }

  let color: Color
  let start: Date
  let frozen: Bool
  @Environment(\.colorScheme) private var scheme
  @State private var played = false

  var body: some View {
    Group {
      if played && !frozen {
        Color.clear
      } else {
        wave
      }
    }
    .allowsHitTesting(false)
    .task(id: start) {
      played = false
      let left = Self.duration - Date.now.timeIntervalSince(start)
      if left > 0 { try? await Task.sleep(for: .seconds(left)) }
      if !Task.isCancelled { played = true }
    }
  }

  private var wave: some View {
    TimelineView(.animation(paused: frozen)) { context in
      let elapsed = frozen ? 0.56 : max(0, context.date.timeIntervalSince(start))
      let envelope = Self.overallEnvelope(at: elapsed)
      let ripple = 0.5 - 0.5 * cos(min(elapsed, Self.duration) * .pi * 2 / 1.4)
      let edgeAlpha = (0.22 + 0.52 * ripple) * envelope
      let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

      ZStack {
        Canvas { canvas, size in
          guard envelope > 0 else { return }
          let cw = size.width / CGFloat(Self.columns)
          let ch = size.height / CGFloat(Self.rows)
          let peakOpacity = scheme == .dark ? 0.62 : 0.48
          for tile in Self.grid {
            let rect = CGRect(x: CGFloat(tile.column) * cw, y: CGFloat(tile.row) * ch, width: cw, height: ch)
            var gridEdge = Path()
            gridEdge.move(to: CGPoint(x: rect.minX, y: rect.maxY - 0.25))
            gridEdge.addLine(to: CGPoint(x: rect.maxX - 0.25, y: rect.maxY - 0.25))
            gridEdge.addLine(to: CGPoint(x: rect.maxX - 0.25, y: rect.minY))
            canvas.stroke(gridEdge, with: .color(color.opacity(0.32 * envelope)), lineWidth: 0.5)

            guard tile.filled else { continue }
            let fillFactor = Self.tileIntensity(distance: tile.distance, at: elapsed)
            guard fillFactor > 0.005 else { continue }
            canvas.fill(Path(rect), with: .color(color.opacity(fillFactor * peakOpacity * envelope)))
          }
        }
        .mask { horizontalFeather }
        .mask { verticalFeather }

        if edgeAlpha > 0.005 {
          shape.strokeBorder(color.opacity(edgeAlpha * 0.6), lineWidth: 1)
        }
      }
    }
  }

  private var horizontalFeather: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .clear, location: 0.14),
        .init(color: .black, location: 0.42),
        .init(color: .black, location: 0.88),
        .init(color: .clear, location: 1),
      ],
      startPoint: .leading, endPoint: .trailing)
  }

  private var verticalFeather: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.35),
        .init(color: .black, location: 0.65),
        .init(color: .clear, location: 1),
      ],
      startPoint: .top, endPoint: .bottom)
  }

  private static func overallEnvelope(at elapsed: TimeInterval) -> Double {
    guard elapsed < duration else { return 0 }
    if elapsed <= duration - 0.4 { return 1 }
    return max(0, (duration - elapsed) / 0.4)
  }

  private static func tileIntensity(distance: Double, at elapsed: TimeInterval) -> Double {
    let shifted = elapsed - distance * 0.42
    guard shifted >= 0, shifted < 4.2 else { return 0 }
    let progress = shifted.truncatingRemainder(dividingBy: 1.4) / 1.4
    if progress < 0.26 { return progress / 0.26 }
    if progress < 0.52 { return 1 - (1 - 0.18) * ((progress - 0.26) / 0.26) }
    return 0.18 * (1 - (progress - 0.52) / 0.48)
  }
}
