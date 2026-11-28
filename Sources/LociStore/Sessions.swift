import Foundation
import GRDB
import LociModel

/// What a session works for: one conversation, or the review of one day.
public enum SessionOwner: Hashable, Sendable {
  case conversation(ConversationRef)
  case review(Day)
  /// Refreshing the panel by this name.
  case panel(String)
  /// A run in the background.
  case run(EntityID)

  /// How the owner is written in the database and in the names of the conversation copies.
  var key: String {
    switch self {
    case .conversation(.main): "main"
    case .conversation(.item(let item)): "library-\(item)"
    case .conversation(.course(let course)): "courses-\(course)"
    case .conversation(.project(let project)): "projects-\(project)"
    case .review(let day): "review-\(day)"
    case .panel(let name): "panel-\(name)"
    case .run(let run): "run-\(run)"
    }
  }

  init?(key: String) {
    if key == "main" {
      self = .conversation(.main)
    } else if key.hasPrefix("library-"), let item = EntityID(canonical: String(key.dropFirst(8))) {
      self = .conversation(.item(item))
    } else if key.hasPrefix("courses-"), let course = EntityID(canonical: String(key.dropFirst(8))) {
      self = .conversation(.course(course))
    } else if key.hasPrefix("projects-"), let project = EntityID(canonical: String(key.dropFirst(9))) {
      self = .conversation(.project(project))
    } else if key.hasPrefix("review-"), let day = Day(String(key.dropFirst(7))) {
      self = .review(day)
    } else if key.hasPrefix("run-"), let run = EntityID(canonical: String(key.dropFirst(4))) {
      self = .run(run)
    } else if key.hasPrefix("panel-"), key.count > 6 {
      self = .panel(String(key.dropFirst(6)))
    } else {
      return nil
    }
  }
}

/// One agent CLI session. A conversation goes through many; the person sees one conversation.
public struct SessionRecord: Hashable, Sendable {
  public let id: EntityID
  public let owner: SessionOwner
  public let runtime: Runtime
  /// The provider's own name for the session, once it has started.
  public let handle: String?
  /// The hash of the `AGENTS.md` the session was opened with.
  public let instructions: String
  /// What the session has been shown of files that change, by name, as hashes: shown once, shown again
  /// only when changed.
  public let sent: [String: String]
  public let startedAt: Timestamp

  public init(
    id: EntityID, owner: SessionOwner, runtime: Runtime, handle: String? = nil, instructions: String,
    sent: [String: String] = [:], startedAt: Timestamp
  ) {
    self.id = id
    self.owner = owner
    self.runtime = runtime
    self.handle = handle
    self.instructions = instructions
    self.sent = sent
    self.startedAt = startedAt
  }
}

extension StoreDatabase {
  /// Starts a session, taking over `messages` already stored in another of the owner's sessions, such as
  /// the prompt of the turn it is opened for. A session the move leaves with no messages is gone.
  public func start(_ session: SessionRecord, taking messages: [EntityID] = []) throws {
    let ids = messages.map(\.description)
    let marks = ids.map { _ in "?" }.joined(separator: ", ")
    try queue.write { db in
      try Self.insert(session, in: db)
      guard !ids.isEmpty else { return }
      let left = try String.fetchAll(
        db, sql: "SELECT DISTINCT session_id FROM message WHERE id IN (\(marks))", arguments: StatementArguments(ids))
      try db.execute(
        sql: "UPDATE message SET session_id = ? WHERE id IN (\(marks))",
        arguments: StatementArguments([session.id.description] + ids))
      for id in left {
        try db.execute(
          sql: "DELETE FROM session WHERE id = ? AND NOT EXISTS (SELECT 1 FROM message WHERE session_id = ?)",
          arguments: [id, id])
      }
    }
  }

  /// The owner's most recent session.
  public func latestSession(of owner: SessionOwner) throws -> SessionRecord? {
    try queue.read { db in
      try Row.fetchOne(
        db, sql: "SELECT * FROM session WHERE owner = ? ORDER BY seq DESC LIMIT 1", arguments: [owner.key]
      ).flatMap(Self.session)
    }
  }

  /// Sessions that started at `since` or later and have a handle, newest first.
  public func sessions(since: Timestamp) throws -> [SessionRecord] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT * FROM session WHERE handle IS NOT NULL AND started_at >= ? ORDER BY started_at DESC, seq DESC",
        arguments: [since.description]
      ).compactMap(Self.session)
    }
  }

  public func bind(handle: String, to session: EntityID) throws {
    try queue.write { db in
      try db.execute(sql: "UPDATE session SET handle = ? WHERE id = ?", arguments: [handle, session.description])
    }
  }

  public func markSent(_ sent: [String: String], in session: EntityID) throws {
    let text = try MirrorUpdate.json(sent)
    try queue.write { db in
      try db.execute(sql: "UPDATE session SET sent = ? WHERE id = ?", arguments: [text, session.description])
    }
  }

  /// Adds messages after every message already in the session, all of them or none.
  public func append(_ messages: [Message], to session: EntityID) throws {
    let rows = try messages.map { ($0, try MirrorUpdate.json($0.body)) }
    try queue.write { db in
      for (message, body) in rows {
        try db.execute(
          sql: "INSERT INTO message (id, session_id, at, typed, body) VALUES (?, ?, ?, ?, ?)",
          arguments: [message.id.description, session.description, message.at.description, message.isTyped, body])
      }
    }
  }

  /// Whether a message with the id was kept, in any session.
  public func hasMessage(_ id: EntityID) throws -> Bool {
    try queue.read { db in
      try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM message WHERE id = ?)", arguments: [id.description])
        ?? false
    }
  }

  /// Every message of every session the owner had, oldest first. A row that cannot be read is left out
  /// rather than hiding the rest.
  public func messages(of owner: SessionOwner) throws -> [Message] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT m.id, m.at, m.body FROM message m JOIN session s ON s.id = m.session_id
          WHERE s.owner = ? ORDER BY m.seq
          """,
        arguments: [owner.key]
      ).compactMap(Self.message)
    }
  }

  /// An item's conversation goes with the item.
  public func deleteConversation(on item: EntityID) throws {
    try deleteConversation(.item(item))
  }

  public func deleteConversation(_ conversation: ConversationRef) throws {
    let owner = SessionOwner.conversation(conversation).key
    try queue.write { db in
      try db.execute(
        sql: "DELETE FROM message WHERE session_id IN (SELECT id FROM session WHERE owner = ?)", arguments: [owner])
      try db.execute(sql: "DELETE FROM session WHERE owner = ?", arguments: [owner])
      try db.execute(sql: "DELETE FROM conversation_runtime WHERE owner = ?", arguments: [owner])
    }
  }

  /// When the companion last said something in the conversation; `nil` before it ever did.
  public func latestReply(in conversation: ConversationRef) throws -> Timestamp? {
    try queue.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT max(m.at) FROM message m JOIN session s ON s.id = m.session_id WHERE s.owner = ? AND NOT m.typed",
        arguments: [SessionOwner.conversation(conversation).key]
      ).flatMap(Timestamp.init)
    }
  }

  /// The text of the companion's latest reply, or of what it said on its own, in the conversation; `nil`
  /// before it said anything. Only the newest messages are read, since a turn ends with what it said.
  public func lastSaid(in conversation: ConversationRef) throws -> String? {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT m.id, m.at, m.body FROM message m JOIN session s ON s.id = m.session_id
          WHERE s.owner = ? AND NOT m.typed ORDER BY m.seq DESC LIMIT 64
          """,
        arguments: [SessionOwner.conversation(conversation).key]
      ).lazy.compactMap(Self.message).compactMap { message -> String? in
        switch message.body {
        case .reply(let text), .told(let text): text
        case .prompt, .thinking, .tool, .savedToNote, .savedItem, .notice, .ended, .startedOver: nil
        }
      }.first
    }
  }

  /// What the person has said to Loci, in every conversation.
  public func talk() throws -> Talk {
    try queue.read { db in
      let typed = "m.typed AND \(Self.conversational)"
      let first = try String.fetchOne(
        db, sql: "SELECT min(m.at) FROM message m JOIN session s ON s.id = m.session_id WHERE \(typed)")
      let latest = try String.fetchOne(
        db,
        sql: """
          SELECT max(m.at) FROM message m JOIN session s ON s.id = m.session_id WHERE \(Self.conversational)
          """)
      let count = try Int.fetchOne(
        db, sql: "SELECT count(*) FROM message m JOIN session s ON s.id = m.session_id WHERE \(typed)")
      let items = try Int.fetchOne(
        db,
        sql: """
          SELECT count(DISTINCT s.owner) FROM message m JOIN session s ON s.id = m.session_id
          WHERE s.owner LIKE 'library-%'
          """)
      return Talk(
        messages: count ?? 0, itemsTalkedAbout: items ?? 0, first: first.flatMap(Timestamp.init),
        latest: latest.flatMap(Timestamp.init))
    }
  }

  /// How many messages the person sent in conversations from `start` up to `end`.
  public func typedMessages(from start: Timestamp, to end: Timestamp) throws -> Int {
    try queue.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT count(*) FROM message m JOIN session s ON s.id = m.session_id
          WHERE m.typed AND \(Self.conversational) AND m.at >= ? AND m.at < ?
          """,
        arguments: [start.description, end.description]) ?? 0
    }
  }

  /// Sessions of a conversation, not of the daily review or a panel's refresh.
  private static let conversational = "s.owner NOT LIKE 'review-%' AND s.owner NOT LIKE 'panel-%'"

  private static func insert(_ session: SessionRecord, in db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO session (id, owner, provider, model, effort, handle, instructions, sent, started_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        session.id.description, session.owner.key, session.runtime.provider.rawValue, session.runtime.model,
        session.runtime.effort?.rawValue, session.handle, session.instructions, try MirrorUpdate.json(session.sent),
        session.startedAt.description,
      ])
  }

  static func message(_ row: Row) -> Message? {
    let id: String = row["id"]
    let at: String = row["at"]
    let body: String = row["body"]
    guard let id = EntityID(canonical: id), let at = Timestamp(at),
      let body = try? JSONDecoder().decode(Message.Body.self, from: Data(body.utf8))
    else { return nil }
    return Message(id: id, at: at, body: body)
  }

  private static func session(_ row: Row) -> SessionRecord? {
    let id: String = row["id"]
    let owner: String = row["owner"]
    let provider: String = row["provider"]
    let effort: String? = row["effort"]
    let sent: String = row["sent"]
    let started: String = row["started_at"]
    guard let id = EntityID(canonical: id), let owner = SessionOwner(key: owner),
      let provider = Provider(rawValue: provider), let startedAt = Timestamp(started)
    else { return nil }
    return SessionRecord(
      id: id, owner: owner,
      runtime: Runtime(provider: provider, model: row["model"], effort: effort.flatMap(ThinkingEffort.init)),
      handle: row["handle"], instructions: row["instructions"],
      sent: (try? JSONDecoder().decode([String: String].self, from: Data(sent.utf8))) ?? [:], startedAt: startedAt)
  }
}

/// How much the person and Loci have talked.
public struct Talk: Hashable, Sendable {
  /// Messages the person sent.
  public let messages: Int
  /// Items whose conversation has a message.
  public let itemsTalkedAbout: Int
  /// When the person first wrote.
  public let first: Timestamp?
  /// When anything was last said in a conversation, by either side.
  public let latest: Timestamp?
}
