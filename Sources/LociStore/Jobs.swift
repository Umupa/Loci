import Foundation
import GRDB
import LociModel

/// Where each item's job stands, kept across launches. Progress within a stage is not stored: a job that
/// was running when the app quit starts its stage again, from the files that stage left.
extension StoreDatabase {
  public func jobs() throws -> [Job] {
    try queue.read { db in
      try Row.fetchAll(db, sql: "SELECT item_id, stage, state FROM job ORDER BY updated_at, item_id").compactMap(
        Self.job)
    }
  }

  public func job(of item: EntityID) throws -> Job? {
    try queue.read { db in
      try Row.fetchOne(
        db, sql: "SELECT item_id, stage, state FROM job WHERE item_id = ?", arguments: [item.description]
      )
      .flatMap(Self.job)
    }
  }

  public func save(_ job: Job, at time: Timestamp) throws {
    let state = String(decoding: try JSONEncoder().encode(job.state), as: UTF8.self)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO job (item_id, stage, state, updated_at) VALUES (?, ?, ?, ?)
          ON CONFLICT(item_id) DO UPDATE SET
            stage = excluded.stage, state = excluded.state, updated_at = excluded.updated_at
          """,
        arguments: [job.item.description, job.stage.rawValue, state, time.description])
    }
  }

  public func deleteJob(of item: EntityID) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM job WHERE item_id = ?", arguments: [item.description])
    }
  }

  private static func job(_ row: Row) -> Job? {
    let id: String = row["item_id"]
    let stage: String = row["stage"]
    let state: String = row["state"]
    guard let item = EntityID(canonical: id), let stage = Job.Stage(rawValue: stage),
      let state = try? JSONDecoder().decode(Job.State.self, from: Data(state.utf8))
    else { return nil }
    return Job(item: item, stage: stage, state: state)
  }
}
