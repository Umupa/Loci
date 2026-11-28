import Foundation
import LociModel
import LociStore

/// Which events the worker takes together, and which wait for their home's budget.
extension Worker {
  /// Whether a home started `wakesPerHour` runs for what descends from its findings and follow-ups in the hour
  /// up to `now`; one that waits for it starts once the hour moves on, unless its deadline passes first.
  func budgetSpent(at now: Timestamp) -> (Home) -> Bool {
    let since = Timestamp(millisecondsSince1970: now.millisecondsSince1970 - 3_600_000)
    var started: [Home: Int] = [:]
    return { [context] home in
      if started[home] == nil { started[home] = (try? context.database.wakeUps(in: home, since: since)) ?? .max }
      return (started[home] ?? .max) >= Self.wakesPerHour
    }
  }

  /// The events that share a run with `first`: those of its home raised for the first time, due in the same
  /// minute. A review, a repair, a follow-up, an event with a deadline, and a run being tried again, run alone.
  static func together(_ events: [Event], first: Event) -> [Event] {
    guard case .waiting(nil) = first.state, !first.runsAlone else { return [first] }
    let minute = first.due.millisecondsSince1970 / 60_000
    return events.filter { event in
      guard case .waiting(nil) = event.state, event.source.home == first.source.home else { return false }
      return !event.runsAlone && !event.isAsked && event.due.millisecondsSince1970 / 60_000 == minute
    }
  }
}
