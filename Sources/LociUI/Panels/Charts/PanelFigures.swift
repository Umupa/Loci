import LociModel
import SwiftUI

/// The snapshots chart rows read their numbers from, and the home whose sources they are.
struct PanelData: Equatable {
  var readings = PanelReadings()
  var home = Home.chat

  func number(_ number: PanelNumber) -> Double? { readings.number(number, of: home) }
  func number(_ number: PanelNumber?) -> Double? { number.flatMap { readings.number($0, of: home) } }
  func text(_ text: PanelText?) -> String? { text.flatMap { readings.text($0, of: home) } }
  func value(_ field: SourceField) -> SourceValue? { readings.value(field, of: home) }
  func key(_ field: SourceField) -> SourceKey { SourceKey(home, field.source) }
}

extension EnvironmentValues {
  @Entry var panelData = PanelData()
}

/// How chart rows write numbers: digits grouped the same in either language, a dash for one not got yet,
/// changes signed with a true minus.
enum PanelFigures {
  static let missing = "—"
  private static let locale = Locale(identifier: "en_US")

  static func number(_ value: Double?, style: PanelStyle, defaultDigits: Int = 2) -> String {
    guard let value, value.isFinite else { return missing }
    let digits = style.digits ?? defaultDigits
    let written: String
    switch style.format {
    case .percent:
      written = plain(value * 100, digits: digits) + "%"
    case .number:
      written = plain(value, digits: digits)
    }
    return style.unit.map { "\(written) \($0)" } ?? written
  }

  /// `0.0118` is `+1.18%`, `-0.0186` is `−1.86%`.
  static func change(_ value: Double?, digits: Int = 2) -> String {
    guard let value, value.isFinite else { return missing }
    let rounded = (value * 100 * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
    let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : ""
    return sign + plain(abs(rounded), digits: digits) + "%"
  }

  static func plain(_ value: Double, digits: Int) -> String {
    let written = value.formatted(
      .number.locale(locale).grouping(.automatic).precision(.fractionLength(digits)))
    return written.replacing("-", with: "−")
  }

  /// Red for up, green for down, ink for neither.
  /// A zone's stop under its bar, with no digits it does not need: `0`, `3%`, `12.5%`.
  static func stop(_ value: Double, style: PanelStyle) -> String {
    guard value != 0 else { return "0" }
    let digits = style.digits ?? 2
    let shown = style.format == .percent ? value * 100 : value
    let written = shown.formatted(.number.locale(locale).grouping(.automatic).precision(.fractionLength(0...digits)))
      .replacing("-", with: "−")
    if style.format == .percent { return written + "%" }
    return style.unit.map { "\(written) \($0)" } ?? written
  }

  /// The block a change is written on: red up, green down, soft in the dark.
  static func block(_ change: Double?) -> Color {
    guard let change, change.isFinite, abs(change) >= 0.00005 else { return Palette.fill }
    return change > 0 ? Palette.riseBlock : Palette.fallBlock
  }

  static func tone(_ change: Double?) -> Color {
    guard let change, change.isFinite, abs(change) >= 0.00005 else { return Palette.ink }
    return change > 0 ? Palette.rise : Palette.fall
  }
}

/// The share of the way from `low` to `high` that `value` is, kept from 0 to 1.
func panelShare(_ value: Double, from low: Double, to high: Double) -> Double {
  guard high > low else { return 0 }
  return min(max((value - low) / (high - low), 0), 1)
}
