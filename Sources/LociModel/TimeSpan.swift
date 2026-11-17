/// A moment or a stretch of time in a video or audio item, to the millisecond.
///
/// Written `t=<start>` or `t=<start>,<end>` in seconds.
public struct TimeSpan: Hashable, Sendable {
  private let startMilliseconds: Int
  private let endMilliseconds: Int?

  /// Rounds both ends to the millisecond. The start is not negative; the end, if any, comes after the start.
  public init(start: Duration, end: Duration? = nil) throws {
    try self.init(milliseconds: start.roundedMilliseconds, end: end?.roundedMilliseconds)
  }

  private init(milliseconds start: Int, end: Int?) throws {
    guard start >= 0 else { throw ModelError("time starts before zero") }
    if let end, end <= start { throw ModelError("time ends before it starts") }
    startMilliseconds = start
    endMilliseconds = end
  }

  public var start: Duration { .milliseconds(startMilliseconds) }
  public var end: Duration? { endMilliseconds.map { .milliseconds($0) } }

  init?(fragmentValue: String) {
    let bounds = fragmentValue.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard (1...2).contains(bounds.count), let start = FixedPoint.units(bounds[0], decimals: 3) else { return nil }
    var end: Int?
    if bounds.count == 2 {
      guard let value = FixedPoint.units(bounds[1], decimals: 3) else { return nil }
      end = value
    }
    guard let span = try? TimeSpan(milliseconds: start, end: end) else { return nil }
    self = span
  }

  var fragment: String {
    let bounds = [startMilliseconds] + (endMilliseconds.map { [$0] } ?? [])
    return "t=" + bounds.map { FixedPoint.text($0, decimals: 3) }.joined(separator: ",")
  }
}
