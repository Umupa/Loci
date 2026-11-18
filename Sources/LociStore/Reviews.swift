import Foundation
import GRDB
import LociModel

/// How a day's review went.
public enum ReviewOutcome: Hashable, Sendable {
  /// Started and not yet over; also a review the app quit during.
  case started
  case finished
  /// The words of the failure.
  case failed(String)
}

extension StoreDatabase {
  /// Records that the day's review began. Throws `alreadyReviewed` when one began before: a day is
  /// looked back on once.
  public func beginReview(of day: Day, at moment: Timestamp) throws {
    try queue.write { db in
      guard try String.fetchOne(db, sql: "SELECT day FROM review WHERE day = ?", arguments: [day.description]) == nil
      else { throw StoreDatabaseError.alreadyReviewed(day) }
      try db.execute(
        sql: "INSERT INTO review (day, started_at) VALUES (?, ?)", arguments: [day.description, moment.description])
    }
  }

  public func endReview(of day: Day, _ outcome: ReviewOutcome) throws {
    let text: String? =
      switch outcome {
      case .started: nil
      case .finished: "finished"
      case .failed(let reason): "failed: " + reason
      }
    try queue.write { db in
      try db.execute(sql: "UPDATE review SET outcome = ? WHERE day = ?", arguments: [text, day.description])
    }
  }

  /// Forgets that the day's review began, for one cut short, so it is done again.
  public func forgetReview(of day: Day) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM review WHERE day = ?", arguments: [day.description])
    }
  }

  /// `nil` when the day was never reviewed.
  public func review(of day: Day) throws -> ReviewOutcome? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(db, sql: "SELECT outcome FROM review WHERE day = ?", arguments: [day.description])
      else { return nil }
      let outcome: String? = row["outcome"]
      switch outcome {
      case nil: return .started
      case "finished": return .finished
      case let text?: return .failed(String(text.dropFirst("failed: ".count)))
      }
    }
  }

  /// When the review before `day` began, if there was one.
  public func latestReview(before day: Day) throws -> (day: Day, startedAt: Timestamp)? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT day, started_at FROM review WHERE day < ? ORDER BY day DESC LIMIT 1",
          arguments: [day.description]),
        let reviewed = Day(row["day"] as String), let started = Timestamp(row["started_at"] as String)
      else { return nil }
      return (reviewed, started)
    }
  }
}
