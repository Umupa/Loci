/// A mentor's accent color, written `#rrggbb`.
public struct MentorColor: Hashable, Sendable, TextCodable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// Parses `#rrggbb` in either case.
  public init?(_ description: String) {
    let digits = description.dropFirst().lowercased()
    guard description.hasPrefix("#"), digits.utf8.count == 6, digits.isLowercaseHex,
      let value = UInt32(digits, radix: 16)
    else { return nil }
    self.init(
      red: UInt8(value >> 16), green: UInt8(truncatingIfNeeded: value >> 8), blue: UInt8(truncatingIfNeeded: value))
  }

  public var description: String {
    "#" + [red, green, blue].map { String($0, radix: 16).leftPadded(to: 2) }.joined()
  }
}

extension String {
  func leftPadded(to width: Int) -> String {
    String(repeating: "0", count: max(0, width - count)) + self
  }
}
