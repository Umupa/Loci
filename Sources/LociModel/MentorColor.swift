/// A mentor's accent color, written `#rrggbb`.
public struct MentorColor: Hashable, Sendable, TextCodable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  /// The colors new mentors are given, in order.
  ///
  /// Carried over from the previous version; the palette is retuned with the visual design.
  public static let palette = [
    MentorColor(red: 0x45, green: 0x9B, blue: 0xF7), MentorColor(red: 0xEA, green: 0x60, blue: 0x3E),
    MentorColor(red: 0xF4, green: 0xC0, blue: 0x25), MentorColor(red: 0x39, green: 0xC6, blue: 0x6D),
    MentorColor(red: 0xE2, green: 0x5A, blue: 0x9E), MentorColor(red: 0xB0, green: 0x69, blue: 0xD3),
    MentorColor(red: 0x37, green: 0xBE, blue: 0xB3), MentorColor(red: 0xEF, green: 0x85, blue: 0x39),
    MentorColor(red: 0x6E, green: 0x63, blue: 0xE9),
  ]

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
