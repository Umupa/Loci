import Foundation

/// A moment to the millisecond, written as ISO 8601 in UTC with milliseconds: `2026-11-17T08:30:00.123Z`.
///
/// Stored as whole milliseconds, so a moment read back from a file equals the one written.
public struct Timestamp: Hashable, Comparable, Sendable, TextCodable {
  public let millisecondsSince1970: Int64

  public init(millisecondsSince1970: Int64) {
    self.millisecondsSince1970 = millisecondsSince1970
  }

  /// Rounds `date` to the nearest millisecond.
  public init(_ date: Date) {
    self.init(millisecondsSince1970: Int64((date.timeIntervalSince1970 * 1000).rounded()))
  }

  public var date: Date { Date(timeIntervalSince1970: Double(millisecondsSince1970) / 1000) }

  public init?(_ description: String) {
    guard let match = description.wholeMatch(of: /(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)\.(\d{3})Z/),
      let seconds = try? Date.ISO8601FormatStyle().parse("\(match.1)Z"), let milliseconds = Int64(match.2)
    else { return nil }
    self.init(millisecondsSince1970: Int64(seconds.timeIntervalSince1970) * 1000 + milliseconds)
  }

  public var description: String {
    let (seconds, milliseconds) = millisecondsSince1970.floorDividedBy1000
    let whole = Date(timeIntervalSince1970: Double(seconds)).formatted(Date.ISO8601FormatStyle())
    return "\(whole.dropLast()).\(String(milliseconds).leftPadded(to: 3))Z"
  }

  public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool {
    lhs.millisecondsSince1970 < rhs.millisecondsSince1970
  }
}

extension Int64 {
  fileprivate var floorDividedBy1000: (quotient: Int64, remainder: Int64) {
    let remainder = ((self % 1000) + 1000) % 1000
    return ((self - remainder) / 1000, remainder)
  }
}
