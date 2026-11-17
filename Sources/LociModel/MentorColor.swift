/// A mentor's accent color, written `#rrggbb`.
public struct MentorColor: Hashable, Sendable, TextCodable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  /// The colours new mentors are given: warm and muted, each dark enough under a white sign.
  public static let palette = [
    MentorColor(red: 0xB0, green: 0x7A, blue: 0x2A), MentorColor(red: 0xB4, green: 0x5A, blue: 0x3C),
    MentorColor(red: 0x76, green: 0x7A, blue: 0x34), MentorColor(red: 0x4D, green: 0x6A, blue: 0x8C),
    MentorColor(red: 0x7D, green: 0x48, blue: 0x68), MentorColor(red: 0x58, green: 0x78, blue: 0x49),
    MentorColor(red: 0xA6, green: 0x52, blue: 0x68), MentorColor(red: 0x3C, green: 0x76, blue: 0x70),
    MentorColor(red: 0x8A, green: 0x5F, blue: 0x3E), MentorColor(red: 0x67, green: 0x59, blue: 0x8C),
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
