import Charts
import LociModel
import SwiftUI

/// Candles, the newest on the right, with dashed lines at the prices set to take profit or stop a loss.
struct PanelCandlesView: View {
  let candles: PanelCandles
  @Environment(\.panelData) private var data
  @State private var width: CGFloat = 340

  var body: some View {
    let shown = self.shown
    let lines = candles.lines.compactMap { line in data.number(line.price).map { (line, $0) } }
    let prices = shown.flatMap { [$0.low, $0.high] } + lines.map(\.1)
    let low = prices.min() ?? 0
    let high = prices.max() ?? 1
    let pad = max((high - low) * 0.05, 0.01)
    let body = max(width / CGFloat(max(shown.count, 1)) * 0.64, 1)
    Chart {
      ForEach(Array(shown.enumerated()), id: \.offset) { index, candle in
        let tone = candle.close >= candle.open ? Palette.rise : Palette.fall
        RuleMark(x: .value("day", index), yStart: .value("low", candle.low), yEnd: .value("high", candle.high))
          .foregroundStyle(tone)
          .lineStyle(StrokeStyle(lineWidth: 1))
        RectangleMark(
          x: .value("day", index), yStart: .value("open", candle.open),
          yEnd: .value("close", candle.close == candle.open ? candle.open + pad * 0.05 : candle.close),
          width: .fixed(body)
        )
        .foregroundStyle(tone)
        .clipShape(.rect(cornerRadius: 1))
      }
      if let last = shown.last {
        RuleMark(y: .value("price", last.close))
          .foregroundStyle(Palette.ink.opacity(0.5))
          .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [1, 2]))
      }
      ForEach(Array(lines.enumerated()), id: \.offset) { _, entry in
        let tone = entry.0.kind == .take ? Palette.rise : Palette.fall
        RuleMark(y: .value("line", entry.1))
          .foregroundStyle(tone)
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
          .annotation(position: .overlay, alignment: .trailing) {
            Text(
              verbatim:
                "\(entry.0.name) \(PanelFigures.number(entry.1, style: PanelStyle(digits: candles.digits), defaultDigits: 0))"
            )
            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(tone)
            .padding(.horizontal, 6).frame(height: 18)
            .background(Palette.surface, in: .rect(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tone, lineWidth: 1))
          }
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartXScale(domain: -0.5...(Double(max(shown.count, 1)) - 0.5))
    .chartYScale(domain: (low - pad)...(high + pad))
    .frame(height: 150)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.width
    } action: {
      width = $0
    }
    .padding(.bottom, Spacing.xs)
  }

  private var shown: [SourceCandle] {
    guard case .candles(let all) = data.value(candles.series) else { return [] }
    return Array(all.sorted { $0.at < $1.at }.suffix(SourceHistory.mostCandles))
  }
}
