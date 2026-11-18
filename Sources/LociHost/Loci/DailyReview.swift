import Foundation
import LociModel

/// When Loci looks back on a day: once a day, after 23:00 when nothing is going on, or the next day for a
/// day that was missed. A day nothing happened on is not looked back on.
enum DailyReview {
  static let hour = 23
  /// How long nothing must have been said before the review starts.
  static let quietMilliseconds: Int64 = 10 * 60 * 1000

  struct Situation {
    let now: Timestamp
    let timeZone: TimeZone
    /// Whether any conversation has a turn running, or a review is under way.
    let working: Bool
    /// When anything was last said in a conversation.
    let lastSaid: Timestamp?
    let reviewed: (Day) -> Bool
    /// Whether anything was said or noted on the day.
    let active: (Day) -> Bool
  }

  /// The day to look back on now, if any.
  static func due(_ situation: Situation) -> Day? {
    guard !situation.working else { return nil }
    let today = Day(containing: situation.now, in: situation.timeZone)
    let yesterday = today.adding(days: -1)
    if !situation.reviewed(yesterday), situation.active(yesterday) { return yesterday }
    let late = TimeOfDay(of: situation.now, in: situation.timeZone).hour >= hour
    let quiet = situation.lastSaid.map {
      situation.now.millisecondsSince1970 - $0.millisecondsSince1970 >= quietMilliseconds
    }
    if late, quiet ?? true, !situation.reviewed(today), situation.active(today) { return today }
    return nil
  }
}
