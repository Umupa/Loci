/// Decimal text for whole numbers of a fixed fraction, such as milliseconds written as seconds.
enum FixedPoint {
  static func text(_ units: Int, decimals: Int) -> String {
    let scale = UInt(power(decimals))
    let whole = units.magnitude / scale
    let fraction = units.magnitude % scale
    let sign = units < 0 ? "-" : ""
    guard fraction > 0 else { return "\(sign)\(whole)" }
    var digits = String(fraction).leftPadded(to: decimals)
    while digits.hasSuffix("0") { digits.removeLast() }
    return "\(sign)\(whole).\(digits)"
  }

  /// Parses `[-]digits[.digits]` with at most `decimals` digits after the point. Anything finer is rejected.
  static func units(_ text: String, decimals: Int) -> Int? {
    let negative = text.hasPrefix("-")
    let parts = text.dropFirst(negative ? 1 : 0).split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), String(parts[0]).isASCIIDigits, let whole = Int(parts[0]) else { return nil }
    let fraction = parts.count == 2 ? String(parts[1]) : "0"
    guard fraction.isASCIIDigits, fraction.count <= decimals, let fractionUnits = Int(fraction) else { return nil }
    let (scaled, overflow) = whole.multipliedReportingOverflow(by: power(decimals))
    guard !overflow else { return nil }
    let magnitude = scaled + fractionUnits * power(decimals - fraction.count)
    return negative ? -magnitude : magnitude
  }

  private static func power(_ exponent: Int) -> Int {
    (0..<exponent).reduce(1) { value, _ in value * 10 }
  }
}

extension Int {
  init?(digits: String) {
    guard digits.isASCIIDigits, let value = Int(digits) else { return nil }
    self = value
  }
}
