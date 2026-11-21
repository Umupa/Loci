import Foundation
import LociModel

/// When a panel is refreshed in the background: an hour after the last time for `hour`, and at the set
/// time of day, or of the week, for `day` and `week`. A time that passed while the app was closed is made
/// up the next time it looks; only once, however many were missed.
enum PanelSchedule {
  static let hour: Int64 = 60 * 60 * 1000

  /// Whether the panel is due at `now`, refreshed last at `last`; `nil` when it never was.
  static func isDue(_ refresh: PanelRefresh, last: Timestamp?, now: Timestamp, timeZone: TimeZone) -> Bool {
    guard let last else { return true }
    switch refresh.every {
    case .hour:
      return now.millisecondsSince1970 - last.millisecondsSince1970 >= hour
    case .day, .week:
      guard let mark = latestTime(of: refresh, atOrBefore: now, in: timeZone) else { return false }
      return last < mark
    }
  }

  /// The last moment up to `now` the panel was meant to be refreshed at.
  static func latestTime(of refresh: PanelRefresh, atOrBefore now: Timestamp, in timeZone: TimeZone) -> Timestamp? {
    guard let at = refresh.at.flatMap(TimeOfDay.init) else { return nil }
    let today = Day(containing: now, in: timeZone)
    let back = refresh.every == .week ? 7 : 1
    for days in 0...back {
      let day = today.adding(days: -days)
      if refresh.every == .week, weekday(of: day, in: timeZone) != refresh.weekday { continue }
      let moment = Timestamp(
        millisecondsSince1970: day.start(in: timeZone).millisecondsSince1970 + Int64(at.hour * 60 + at.minute) * 60_000)
      if moment <= now { return moment }
    }
    return nil
  }

  private static func weekday(of day: Day, in timeZone: TimeZone) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.component(.weekday, from: day.start(in: timeZone).date)
  }
}
