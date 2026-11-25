import Foundation

/// When a source is fetched again: as often as it says while the window is in front, at most hourly while it
/// is behind, and never outside its window.
public enum SourceSchedule {
  /// The least time between fetches while the window is behind.
  public static let behindMinutes = 60
  /// How early a fetch may come, so a minute's tick that comes a little early still fetches.
  static let slack: Int64 = 5_000

  /// `tried` is when it was last tried, got or not; `nil` when it never was.
  public static func due(
    _ source: DataSource, tried: Timestamp?, now: Timestamp, inFront: Bool, timeZone: TimeZone
  ) -> Bool {
    if let window = source.window, !window.contains(now, in: timeZone) { return false }
    guard let tried else { return true }
    let minutes = Int64(inFront ? source.every.minutes : max(source.every.minutes, behindMinutes))
    return now.millisecondsSince1970 - tried.millisecondsSince1970 >= minutes * 60_000 - slack
  }
}

extension SourceWindow {
  /// Whether the moment falls in the window, the day it falls on counted where the person is.
  public func contains(_ moment: Timestamp, in timeZone: TimeZone) -> Bool {
    if weekdays {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      guard !calendar.isDateInWeekend(moment.date) else { return false }
    }
    let time = TimeOfDay(of: moment, in: timeZone)
    return from <= time && time < to
  }
}
