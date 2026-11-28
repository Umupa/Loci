import Foundation
import GRDB
import LociModel

/// The episodes of each follow (`follow_episode`) and how reading them went (`follow_state`). Both can be read
/// again from the web, so they live in the database only.
extension StoreDatabase {
  /// The most episodes kept for one follow; the oldest go first.
  public static let mostEpisodes = 300

  /// A follow's episodes, newest first, each with when it was first seen.
  public func episodes(of follow: EntityID, limit: Int = mostEpisodes) throws -> [(
    episode: Episode, firstSeen: Timestamp
  )] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT body, first_seen FROM follow_episode WHERE follow = ?
          ORDER BY COALESCE(published, first_seen) DESC, first_seen DESC LIMIT ?
          """,
        arguments: [follow.description, limit]
      ).compactMap { row in
        guard let episode = try? Self.decoded(Episode.self, row["body"]) else { return nil }
        return (episode, Timestamp(millisecondsSince1970: row["first_seen"]))
      }
    }
  }

  /// Keeps what a read of the follow found. An episode not kept before is new when `fresh` and it came out after
  /// the newest one kept, and was seen when the follow started otherwise; one kept before gets what it lacked.
  /// Returns whether anything changed and how many episodes are new.
  @discardableResult
  public func keepEpisodes(_ found: [Episode], of follow: Follow, at now: Timestamp, fresh: Bool) throws
    -> (changed: Bool, new: Int)
  {
    try queue.write { db in
      let id = follow.id.description
      var known: [EpisodeKey: Episode] = [:]
      for body in try String.fetchAll(db, sql: "SELECT body FROM follow_episode WHERE follow = ?", arguments: [id]) {
        if let episode = try? Self.decoded(Episode.self, body) { known[episode.key] = episode }
      }
      let newest = known.values.compactMap(\.published).max()
      let keptAny = !known.isEmpty
      var changed = false
      var new = 0
      for episode in found {
        if let before = known[episode.key] {
          let filled = before.filled(from: episode)
          guard filled != before else { continue }
          try db.execute(
            sql: "UPDATE follow_episode SET body = ?, published = ? WHERE follow = ? AND key = ?",
            arguments: [
              try MirrorUpdate.json(filled), filled.published?.millisecondsSince1970, id, episode.key.description,
            ])
          known[episode.key] = filled
          changed = true
          continue
        }
        let isNew =
          fresh && keptAny && (episode.published.map { published in newest.map { published > $0 } ?? true } ?? true)
        try db.execute(
          sql: "INSERT INTO follow_episode (follow, key, published, first_seen, body) VALUES (?, ?, ?, ?, ?)",
          arguments: [
            id, episode.key.description, episode.published?.millisecondsSince1970,
            (isNew ? now : follow.followed).millisecondsSince1970, try MirrorUpdate.json(episode),
          ])
        known[episode.key] = episode
        changed = true
        if isNew { new += 1 }
      }
      if known.count > Self.mostEpisodes {
        try db.execute(
          sql: """
            DELETE FROM follow_episode WHERE follow = ? AND key NOT IN (
              SELECT key FROM follow_episode WHERE follow = ?
              ORDER BY COALESCE(published, first_seen) DESC, first_seen DESC LIMIT ?)
            """,
          arguments: [id, id, Self.mostEpisodes])
      }
      return (changed, new)
    }
  }

  /// How reading a follow went the last time.
  public struct FollowState: Hashable, Sendable {
    /// When its newest episodes were last read.
    public var tried: Timestamp?
    /// When its past episodes were last listed.
    public var listed: Timestamp?
    public var problem: FollowProblem?

    public init(tried: Timestamp? = nil, listed: Timestamp? = nil, problem: FollowProblem? = nil) {
      self.tried = tried
      self.listed = listed
      self.problem = problem
    }
  }

  public func followStates() throws -> [EntityID: FollowState] {
    try queue.read { db in
      var states: [EntityID: FollowState] = [:]
      for row in try Row.fetchAll(db, sql: "SELECT follow, tried, listed, problem FROM follow_state") {
        guard let id = EntityID(canonical: row["follow"]) else { continue }
        states[id] = Self.state(row)
      }
      return states
    }
  }

  public func followState(_ follow: EntityID) throws -> FollowState {
    try queue.read { db in
      try Row.fetchOne(
        db, sql: "SELECT tried, listed, problem FROM follow_state WHERE follow = ?", arguments: [follow.description]
      ).map(Self.state) ?? FollowState()
    }
  }

  /// Changes how reading the follow went, and gives whether that changed what the person sees: the problem.
  @discardableResult
  public func changeFollowState(_ follow: EntityID, _ change: (inout FollowState) -> Void) throws -> Bool {
    try queue.write { db in
      let id = follow.description
      let before =
        try Row.fetchOne(db, sql: "SELECT tried, listed, problem FROM follow_state WHERE follow = ?", arguments: [id])
        .map(Self.state) ?? FollowState()
      var after = before
      change(&after)
      try db.execute(
        sql: "INSERT OR REPLACE INTO follow_state (follow, tried, listed, problem) VALUES (?, ?, ?, ?)",
        arguments: [
          id, after.tried?.millisecondsSince1970, after.listed?.millisecondsSince1970,
          try after.problem.map { try MirrorUpdate.json($0) },
        ])
      return after.problem != before.problem
    }
  }

  /// Forgets a follow's episodes and how reading them went.
  public func forgetFollow(_ follow: EntityID) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM follow_episode WHERE follow = ?", arguments: [follow.description])
      try db.execute(sql: "DELETE FROM follow_state WHERE follow = ?", arguments: [follow.description])
    }
  }

  private static func state(_ row: Row) -> FollowState {
    FollowState(
      tried: (row["tried"] as Int64?).map(Timestamp.init(millisecondsSince1970:)),
      listed: (row["listed"] as Int64?).map(Timestamp.init(millisecondsSince1970:)),
      problem: (row["problem"] as String?).flatMap { try? decoded(FollowProblem.self, $0) })
  }
}
