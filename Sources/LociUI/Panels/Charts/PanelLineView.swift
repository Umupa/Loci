import Charts
import LociModel
import SwiftUI

/// A large number over a line, with spans to switch between. Hovering puts a crosshair on the nearest
/// point and the large number follows it.
struct PanelLineView: View {
  let chart: PanelLineChart
  /// What each span draws, never empty.
  private let fields: [(span: PanelRange, field: SourceField)]
  @Environment(\.panelData) private var data
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var chosen = 0
  @State private var history: Feed<SourceHistory?>?
  @State private var pointed: SourcePoint?

  /// `nil` for a chart with no span to draw.
  init?(chart: PanelLineChart) {
    let fields = chart.spans.compactMap { span in chart.ranges[span].map { (span, $0) } }
    guard !fields.isEmpty else { return nil }
    self.chart = chart
    self.fields = fields
  }

  var body: some View {
    let points = self.points
    let change =
      pointed.flatMap { point in points.first.map { (point.value - $0.value) / $0.value } }
      ?? data.number(chart.change)
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
        Text(verbatim: PanelFigures.number(pointed?.value ?? data.number(chart.value), style: chart.style))
          .font(.system(size: 28, weight: .semibold)).kerning(-0.5).monospacedDigit()
          .foregroundStyle(Palette.ink)
          .contentTransition(.numericText())
        Text(verbatim: PanelFigures.change(change))
          .font(.system(size: 14, weight: .semibold)).monospacedDigit()
          .foregroundStyle(PanelFigures.tone(change))
          .contentTransition(.numericText())
      }
      .lineLimit(1)
      .animation(reduceMotion ? nil : Motion.quick, value: pointed == nil)
      PanelLineChartView(points: points, pointed: $pointed, style: chart.style)
        .frame(height: 150)
        .id(chosen)
        .transition(reduceMotion ? .identity : .opacity)
      if fields.count > 1 {
        PanelSpans(spans: fields.map(\.span), chosen: $chosen)
      }
    }
    .subscribing(subscription, into: $history)
    .padding(.bottom, Spacing.xs)
  }

  private var subscription: WatchSourceHistory {
    let (span, field) = fields[min(chosen, fields.count - 1)]
    return WatchSourceHistory(data.key(field), field: field, range: span)
  }

  private var points: [SourcePoint] {
    guard case .value(.points(let points)?) = history else { return [] }
    return points
  }
}

private struct PanelLineChartView: View {
  let points: [SourcePoint]
  @Binding var pointed: SourcePoint?
  let style: PanelStyle

  var body: some View {
    let first = points.first?.value
    let tone = PanelFigures.tone(first.flatMap { start in points.last.map { $0.value - start } })
    let values = points.map(\.value)
    let low = values.min() ?? 0
    let high = values.max() ?? 1
    let pad = max((high - low) * 0.08, abs(high) * 0.0005)
    Chart {
      if let first {
        RuleMark(y: .value("start", first))
          .foregroundStyle(Palette.inkFaint)
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
      }
      ForEach(points, id: \.at) { point in
        AreaMark(x: .value("at", point.at.date), yStart: .value("low", low - pad), yEnd: .value("value", point.value))
          .foregroundStyle(
            LinearGradient(colors: [tone.opacity(0.22), tone.opacity(0)], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("at", point.at.date), y: .value("value", point.value))
          .foregroundStyle(tone)
          .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
      }
      if let pointed {
        RuleMark(x: .value("at", pointed.at.date)).foregroundStyle(Palette.lineStrong)
        PointMark(x: .value("at", pointed.at.date), y: .value("value", pointed.value))
          .symbol { Circle().fill(Palette.surface).stroke(tone, lineWidth: 2).frame(width: 9, height: 9) }
          .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
            Text(verbatim: PanelFigures.number(pointed.value, style: style))
              .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
              .foregroundStyle(Palette.canvas)
              .padding(.horizontal, 8).padding(.vertical, 3)
              .background(Palette.ink, in: .rect(cornerRadius: 7, style: .continuous))
          }
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartLegend(.hidden)
    .chartYScale(domain: (low - pad)...(high + pad))
    .chartOverlay { proxy in
      Rectangle().fill(.clear).contentShape(Rectangle())
        .onContinuousHover { phase in
          switch phase {
          case .active(let location):
            guard let date: Date = proxy.value(atX: location.x) else { return }
            pointed = points.min { abs($0.at.date.timeIntervalSince(date)) < abs($1.at.date.timeIntervalSince(date)) }
          case .ended:
            pointed = nil
          }
        }
    }
  }
}

/// The spans a line switches between, as a row of tabs.
private struct PanelSpans: View {
  let spans: [PanelRange]
  /// The index of the span shown.
  @Binding var chosen: Int
  @Environment(\.reducesMotion) private var reduceMotion
  @Namespace private var thumb

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
        let on = index == chosen
        Button {
          withAnimation(reduceMotion ? nil : Motion.quick) { chosen = index }
        } label: {
          Text(.loci(span.label))
            .font(.system(size: 12))
            .foregroundStyle(on ? Palette.ink : Palette.inkMuted)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background {
              if on {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.surface)
                  .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                  .matchedGeometryEffect(id: "thumb", in: thumb)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .padding(2)
    .background(Palette.fillStrong, in: .rect(cornerRadius: 10, style: .continuous))
  }
}

extension PanelRange {
  var label: String.LocalizationValue {
    switch self {
    case .day: "panels.rangeDay"
    case .fiveDays: "panels.rangeFiveDays"
    case .month: "panels.rangeMonth"
    case .year: "panels.rangeYear"
    case .fiveYears: "panels.rangeFiveYears"
    }
  }
}
