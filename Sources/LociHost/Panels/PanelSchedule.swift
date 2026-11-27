import Foundation
import LociModel

/// When a panel is refreshed in the background: its `refresh` read as a schedule (`Every`). A panel never
/// refreshed is due at once; a time that passed while the app was closed is made up once.
enum PanelSchedule {
  /// Whether the panel is due at `now`, refreshed last at `last`; `nil` when it never was.
  static func isDue(_ refresh: PanelRefresh, last: Timestamp?, now: Timestamp, timeZone: TimeZone) -> Bool {
    due(refresh, last: last, now: now, timeZone: timeZone) != nil
  }

  /// The moment it came due at, when it is due.
  static func due(
    _ refresh: PanelRefresh, last: Timestamp?, now: Timestamp, timeZone: TimeZone, trading: TradingCalendar = .bundled
  ) -> Timestamp? {
    Every(refresh)?.due(last: last, now: now, in: timeZone, trading: trading)
  }

  /// The last moment up to `now` the panel was meant to be refreshed at.
  static func latestTime(of refresh: PanelRefresh, atOrBefore now: Timestamp, in timeZone: TimeZone) -> Timestamp? {
    Every(refresh)?.latest(atOrBefore: now, in: timeZone)
  }
}
