import Foundation
import GRDB
import LociModel

/// What the app keeps about a connected connector, beside its credentials in the keychain: every tool it
/// listed, with what each says about writing, so a call is checked without asking the server.
public struct ConnectorRecord: Hashable, Codable, Sendable {
  public let id: ConnectorID
  public let name: String
  public let kind: ConnectorOffer.Kind
  public let server: URL
  public let account: String?
  public let status: Connector.Status
  public let connectedAt: Timestamp
  public let tools: [Tool]
  /// Whether it has credentials in the keychain; an address that needs no sign-in has none.
  public let signedIn: Bool

  public struct Tool: Hashable, Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: String
    /// `nil` when the server does not say.
    public let readOnly: Bool?

    public init(name: String, description: String, inputSchema: String, readOnly: Bool?) {
      self.name = name
      self.description = description
      self.inputSchema = inputSchema
      self.readOnly = readOnly
    }
  }

  public init(
    id: ConnectorID, name: String, kind: ConnectorOffer.Kind, server: URL, account: String?,
    status: Connector.Status, connectedAt: Timestamp, tools: [Tool], signedIn: Bool
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.server = server
    self.account = account
    self.status = status
    self.connectedAt = connectedAt
    self.tools = tools
    self.signedIn = signedIn
  }

  public func with(status: Connector.Status) -> ConnectorRecord {
    ConnectorRecord(
      id: id, name: name, kind: kind, server: server, account: account, status: status, connectedAt: connectedAt,
      tools: tools, signedIn: signedIn)
  }

  public func with(tools: [Tool]) -> ConnectorRecord {
    ConnectorRecord(
      id: id, name: name, kind: kind, server: server, account: account, status: status, connectedAt: connectedAt,
      tools: tools, signedIn: signedIn)
  }
}

extension StoreDatabase {
  public func connectorRecords() throws -> [ConnectorRecord] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM connector ORDER BY id")
        .compactMap { try? Self.decoded(ConnectorRecord.self, $0) }
    }
  }

  public func connectorRecord(_ id: ConnectorID) throws -> ConnectorRecord? {
    try queue.read { db in
      try String.fetchOne(db, sql: "SELECT body FROM connector WHERE id = ?", arguments: [id.rawValue])
        .flatMap { try? Self.decoded(ConnectorRecord.self, $0) }
    }
  }

  public func saveConnector(_ record: ConnectorRecord) throws {
    let body = try MirrorUpdate.json(record)
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO connector (id, body) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET body = excluded.body",
        arguments: [record.id.rawValue, body])
    }
  }

  /// Forgets the connector; its calls stay in the record.
  public func removeConnector(_ id: ConnectorID) throws {
    try queue.write { db in
      try db.execute(sql: "DELETE FROM connector WHERE id = ?", arguments: [id.rawValue])
    }
  }

  /// Websites the person disconnected while still signed into them, so they are not connected again on
  /// their own until the person connects them.
  public func setAsideConnectors() throws -> Set<ConnectorID> {
    try queue.read { db in
      Set(try String.fetchAll(db, sql: "SELECT id FROM connector_set_aside").map(ConnectorID.init(rawValue:)))
    }
  }

  public func setAside(_ id: ConnectorID, _ aside: Bool) throws {
    try queue.write { db in
      if aside {
        try db.execute(sql: "INSERT OR IGNORE INTO connector_set_aside (id) VALUES (?)", arguments: [id.rawValue])
      } else {
        try db.execute(sql: "DELETE FROM connector_set_aside WHERE id = ?", arguments: [id.rawValue])
      }
    }
  }

  public func logConnectorCall(_ call: ConnectorCall) throws {
    let body = try MirrorUpdate.json(call)
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO connector_call (id, at, connector, caller, body) VALUES (?, ?, ?, ?, ?)",
        arguments: [call.id.description, call.at.description, call.connector.rawValue, call.caller.tag, body])
    }
  }

  /// The latest calls, newest first.
  public func connectorCalls(limit: Int) throws -> [ConnectorCall] {
    try queue.read { db in
      try String.fetchAll(db, sql: "SELECT body FROM connector_call ORDER BY seq DESC LIMIT ?", arguments: [limit])
        .compactMap { try? Self.decoded(ConnectorCall.self, $0) }
    }
  }

  /// Calls since `moment`, oldest first.
  public func connectorCalls(since moment: Timestamp) throws -> [ConnectorCall] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM connector_call WHERE at >= ? ORDER BY seq", arguments: [moment.description]
      )
      .compactMap { try? Self.decoded(ConnectorCall.self, $0) }
    }
  }

  /// The calls made from one run or conversation, oldest first.
  public func connectorCalls(by caller: ConnectorCall.Caller) throws -> [ConnectorCall] {
    try queue.read { db in
      try String.fetchAll(
        db, sql: "SELECT body FROM connector_call WHERE caller = ? ORDER BY seq", arguments: [caller.tag]
      )
      .compactMap { try? Self.decoded(ConnectorCall.self, $0) }
    }
  }
}
