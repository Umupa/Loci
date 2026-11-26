import LociModel
import SwiftUI

/// Quotes, one line each: name and code, a small line of the day, the price, and the change in a red or
/// green block. The figures roll to new values, price or change, and change at once when motion is reduced.
struct PanelQuotes: View {
  let quotes: [PanelQuote]
  @Environment(\.panelData) private var data
  @Environment(\.reducesMotion) private var reduceMotion

  /// What a line's figures roll on.
  struct Figures: Equatable {
    let price: Double?
    let change: Double?
  }

  static func motion(reducesMotion: Bool) -> Animation? {
    reducesMotion ? nil : .default
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(quotes.enumerated()), id: \.offset) { index, quote in
        if index > 0 { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
        line(quote).padding(.vertical, Spacing.xs)
      }
    }
  }

  private func line(_ quote: PanelQuote) -> some View {
    let change = data.number(quote.change)
    let price = data.number(quote.price)
    let code = [quote.code, data.text(quote.asOf)].compactMap { $0 }.joined(separator: " · ")
    return HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: quote.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
        if !code.isEmpty {
          Text(verbatim: code).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Palette.inkFaint)
        }
      }
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      PanelSpark(points: spark(quote), change: change).frame(width: 58, height: 24)
      Text(verbatim: PanelFigures.number(price, style: PanelStyle(digits: quote.digits)))
        .font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.ink)
        .contentTransition(.numericText())
        .lineLimit(1).fixedSize()
      Text(verbatim: PanelFigures.change(change))
        .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
        .foregroundStyle(change == nil ? Palette.inkFaint : .white)
        .contentTransition(.numericText())
        .frame(minWidth: 62, minHeight: 24)
        .background(
          PanelFigures.block(change), in: .rect(cornerRadius: 7, style: .continuous))
    }
    .animation(Self.motion(reducesMotion: reduceMotion), value: Figures(price: price, change: change))
  }

  private func spark(_ quote: PanelQuote) -> [SourcePoint] {
    guard let field = quote.spark, case .points(let points) = data.value(field) else { return [] }
    return SourceHistory.cut(points, to: .day, most: 60)
  }
}

/// A small line with a dotted mark where it started.
struct PanelSpark: View {
  let points: [SourcePoint]
  let change: Double?

  var body: some View {
    Canvas { context, size in
      let values = points.map(\.value)
      guard let low = values.min(), let high = values.max(), values.count > 1 else { return }
      let y = { (value: Double) in size.height - 2 - CGFloat(panelShare(value, from: low, to: high)) * (size.height - 4)
      }
      var base = Path()
      base.move(to: CGPoint(x: 0, y: y(values[0])))
      base.addLine(to: CGPoint(x: size.width, y: y(values[0])))
      context.stroke(base, with: .color(Palette.inkFaint), style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 2]))
      var line = Path()
      for (index, value) in values.enumerated() {
        let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1), y: y(value))
        if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
      }
      let tone = PanelFigures.tone(change ?? (values[values.count - 1] - values[0]))
      context.stroke(line, with: .color(tone), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
  }
}
