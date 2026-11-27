import Foundation
import GRDB
import LociModel

/// The models each agent program listed last, so a picker has them before the program answers again. It lives in
/// the database only.
extension StoreDatabase {
  public struct ListedModels: Hashable, Sendable {
    public let models: [AgentModel]
    /// The program's version when it listed them; `nil` when it does not say.
    public let version: String?
    public let listed: Timestamp

    public init(models: [AgentModel], version: String?, listed: Timestamp) {
      self.models = models
      self.version = version
      self.listed = listed
    }
  }

  public func listedModels(of provider: Provider) throws -> ListedModels? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT version, listed, models FROM agent_models WHERE provider = ?",
          arguments: [provider.rawValue]),
        let models = try? JSONDecoder().decode([AgentModel].self, from: Data((row["models"] as String).utf8))
      else { return nil }
      return ListedModels(
        models: models, version: row["version"], listed: Timestamp(millisecondsSince1970: row["listed"]))
    }
  }

  public func keepListedModels(_ listed: ListedModels, of provider: Provider) throws {
    let models = String(decoding: try JSONEncoder().encode(listed.models), as: UTF8.self)
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO agent_models (provider, version, listed, models) VALUES (?, ?, ?, ?)
          ON CONFLICT(provider) DO UPDATE SET version = excluded.version, listed = excluded.listed,
            models = excluded.models
          """,
        arguments: [provider.rawValue, listed.version, listed.listed.millisecondsSince1970, models])
    }
  }
}
