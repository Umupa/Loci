import Foundation
import LociModel

@testable import LociUI

/// An investing column's chart panels and the snapshots of the sources they point at, as the design draws them.
enum SampleChartPanels {
  /// 2026-11-25 11:39 in Shanghai.
  static let now = Timestamp(millisecondsSince1970: 1_764_041_940_000)
  static let minute: Int64 = 60_000

  static func field(_ text: String) -> SourceField { SourceField(text) ?? SourceField("x.x.x")! }
  static func number(_ text: String) -> PanelNumber { .field(field(text)) }

  /// A walk from `start` that ends at `end`, the same every time.
  static func walk(seed: UInt64, count: Int, start: Double, swing: Double, end: Double) -> [Double] {
    var state = seed
    var values = [start]
    for _ in 1..<count {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let step = Double(state >> 33) / Double(1 << 31) - 0.5
      values.append(values[values.count - 1] * (1 + step * swing))
    }
    let drift = (end - values[count - 1]) / Double(count - 1)
    return values.enumerated().map { $0.element + drift * Double($0.offset) }
  }

  static func points(seed: UInt64, count: Int, every: Int64, start: Double, swing: Double, end: Double) -> SourceValue {
    let values = walk(seed: seed, count: count, start: start, swing: swing, end: end)
    return .points(
      values.enumerated().map { index, value in
        SourcePoint(
          at: Timestamp(millisecondsSince1970: now.millisecondsSince1970 - Int64(count - 1 - index) * every),
          value: value)
      })
  }

  static var candles: SourceValue {
    let closes = walk(seed: 42, count: 29, start: 128, swing: 0.06, end: 152.3)
    return .candles(
      (1..<closes.count).map { index in
        let open = closes[index - 1]
        let close = closes[index]
        let wick = abs(close - open) * 0.6 + 1.2
        return SourceCandle(
          at: Timestamp(millisecondsSince1970: now.millisecondsSince1970 - Int64(29 - index) * 1440 * minute),
          open: open, high: max(open, close) + wick, low: min(open, close) - wick * 0.8, close: close)
      })
  }

  static var readings: PanelReadings {
    let day = 1440 * minute
    return PanelReadings([
      SourceKey(.chat, "hold"): SourceSnapshot(
        fetched: now,
        records: [
          "all": ["total": .number(61.8), "change": .number(-0.0091)],
          "513100": [
            "price": .number(1.873), "change": .number(-0.0186),
            "day": points(seed: 11, count: 48, every: 5 * minute, start: 1.9, swing: 0.01, end: 1.873),
            "date": .text("净值 11-23"),
          ],
          "511090": [
            "price": .number(1.142), "change": .number(0.0021),
            "day": points(seed: 12, count: 48, every: 5 * minute, start: 1.139, swing: 0.004, end: 1.142),
          ],
          "512890": [
            "price": .number(1.296), "change": .number(0.0118),
            "day": points(seed: 13, count: 48, every: 5 * minute, start: 1.28, swing: 0.006, end: 1.296),
          ],
          "300308": [
            "price": .number(152.30), "change": .number(-0.034),
            "day": points(seed: 14, count: 48, every: 5 * minute, start: 157, swing: 0.01, end: 152.3),
          ],
        ]),
      SourceKey(.chat, "ndx"): SourceSnapshot(
        fetched: now,
        records: [
          "ndx": [
            "price": .number(20_912), "change": .number(-0.0148),
            "day": points(seed: 85, count: 78, every: 5 * minute, start: 21_224, swing: 0.004, end: 20_912),
            "week": points(seed: 67, count: 60, every: 2 * 60 * minute, start: 21_480, swing: 0.007, end: 20_912),
            "month": points(seed: 51, count: 44, every: day, start: 20_210, swing: 0.012, end: 20_912),
            "year": points(seed: 59, count: 52, every: 7 * day, start: 17_350, swing: 0.03, end: 20_912),
            "fiveYears": points(seed: 67, count: 60, every: 30 * day, start: 11_800, swing: 0.05, end: 20_912),
          ]
        ]),
      SourceKey(.chat, "heat"): SourceSnapshot(
        fetched: now,
        records: Dictionary(
          uniqueKeysWithValues: [
            ("NVDA", 8.0, -0.059), ("MSFT", 6.0, -0.008), ("AAPL", 5.0, 0.004), ("AMZN", 4.0, -0.012),
            ("AVGO", 3.5, -0.047), ("META", 3.0, -0.011), ("GOOGL", 2.6, -0.006), ("TSLA", 2.2, 0.019),
            ("COST", 1.2, 0.003), ("NFLX", 1.0, -0.002), ("HC07", 0.35, 0.024), ("HC08", 0.3, -0.012),
          ].map { ($0.0, ["weight": SourceValue.number($0.1), "change": .number($0.2)]) })),
      SourceKey(.chat, "kline"): SourceSnapshot(fetched: now, records: ["300308": ["daily": candles]]),
      SourceKey(.chat, "prem"): SourceSnapshot(
        fetched: Timestamp(millisecondsSince1970: now.millisecondsSince1970 - 26 * minute), tried: now, failures: 2,
        records: [
          "513870": ["premium": .number(0.159)], "159501": ["premium": .number(0.1925)],
          "159513": ["premium": .number(0.1282)],
        ]),
    ])
  }

  static let hold = Panel(
    name: "hold", title: "持仓", follow: "盯着持仓",
    body: .rows([
      .sentence("今天 **−0.91%**，红利低波超配 2%。"),
      .allocation(
        PanelAllocation(
          total: number("hold.all.total"), change: number("hold.all.change"),
          slices: [
            PanelSlice(name: "纳指100", actual: .fixed(0.58), target: .fixed(0.6)),
            PanelSlice(name: "固收+", actual: .fixed(0.2), target: .fixed(0.2)),
            PanelSlice(name: "红利低波", actual: .fixed(0.17), target: .fixed(0.15)),
            PanelSlice(name: "A 股短线", actual: .fixed(0.05), target: .fixed(0.05)),
          ], style: PanelStyle(digits: 1, unit: "万"))),
      .label("今天"),
      .quotes([
        PanelQuote(
          name: "纳指100 QDII", code: "513100", price: number("hold.513100.price"),
          change: number("hold.513100.change"), spark: field("hold.513100.day"),
          asOf: .field(field("hold.513100.date")),
          digits: 3),
        PanelQuote(
          name: "30年国债ETF", code: "511090", price: number("hold.511090.price"),
          change: number("hold.511090.change"), spark: field("hold.511090.day"), digits: 3),
        PanelQuote(
          name: "红利低波ETF", code: "512890", price: number("hold.512890.price"),
          change: number("hold.512890.change"), spark: field("hold.512890.day"), digits: 3),
        PanelQuote(
          name: "中际旭创", code: "300308", price: number("hold.300308.price"), change: number("hold.300308.change"),
          spark: field("hold.300308.day")),
      ]),
    ]))

  static let index = Panel(
    name: "ndx", title: "纳指100", follow: "盯着纳指",
    body: .rows([
      .line(
        PanelLineChart(
          value: number("ndx.ndx.price"), change: number("ndx.ndx.change"),
          ranges: [
            .day: field("ndx.ndx.day"), .fiveDays: field("ndx.ndx.week"), .month: field("ndx.ndx.month"),
            .year: field("ndx.ndx.year"), .fiveYears: field("ndx.ndx.fiveYears"),
          ], style: PanelStyle(digits: 0))),
      .ruler(
        PanelRuler(
          label: "市盈率 · 近五年分位", value: .fixed(31.4), share: .fixed(0.72), low: .fixed(22.1), high: .fixed(36.8),
          style: PanelStyle(digits: 1))),
    ]))

  static let heat = Panel(
    name: "heat", title: "十大成分股", follow: "盯着成分股",
    body: .rows([
      .sentence("**英伟达 −5.9%**，拖累指数约 0.6 个点。"),
      .heat(
        ["NVDA", "MSFT", "AAPL", "AMZN", "AVGO", "META", "GOOGL", "TSLA", "COST", "NFLX", "HC07", "HC08"].map {
          PanelHeatTile(code: $0, weight: number("heat.\($0).weight"), change: number("heat.\($0).change"))
        }),
    ]))

  static let kline = Panel(
    name: "kline", title: "中际旭创", follow: "盯着止盈止损",
    body: .rows([
      .sentence("离止损还有 **9.4%**，持有 12 天。"),
      .candles(
        PanelCandles(
          series: field("kline.300308.daily"),
          lines: [
            PanelPriceLine(name: "止盈", price: .fixed(172), kind: .take),
            PanelPriceLine(name: "止损", price: .fixed(138), kind: .stop),
          ])),
    ]))

  static let premium = Panel(
    name: "prem", title: "ETF 溢价", follow: "盯着溢价",
    body: .rows([
      .sentence("三只都在 **10% 以上**，场内先别买。"),
      .zones(
        PanelZones(
          stops: [0, 0.03, 0.1, 0.2],
          rows: [
            PanelZoneRow(name: "513870", note: "你持有", value: number("prem.513870.premium")),
            PanelZoneRow(name: "159501", note: "你持有", value: number("prem.159501.premium")),
            PanelZoneRow(name: "159513", note: "最低", value: number("prem.159513.premium")),
          ], style: PanelStyle(format: .percent, digits: 1))),
    ]))

  static var column: PanelColumn {
    PanelColumn(slots: [hold, index, premium, kline, heat].map(PanelSlot.panel), readings: readings)
  }
}
