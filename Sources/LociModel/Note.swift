import Foundation

/// Something left while reading: a place, and optionally a thought and questions Loci answered.
///
/// A note with neither is a plain highlight.
public struct Note: Hashable, Sendable {
  /// Stays the same across edits.
  public let id: EntityID
  public let locator: Locator
  /// The words or transcript lines that were marked.
  public let excerpt: String?
  public let thought: String?
  /// In the order they were asked. Only finished answers are kept.
  public let exchanges: [Exchange]
  /// When this version was saved. The note was first made at `id.createdAt`.
  public let savedAt: Timestamp

  public init(
    id: EntityID, locator: Locator, excerpt: String? = nil, thought: String? = nil, exchanges: [Exchange] = [],
    savedAt: Timestamp
  ) throws {
    self.id = id
    self.locator = locator
    self.excerpt = try excerpt.requiringText("excerpt")
    self.thought = try thought.requiringText("thought")
    self.exchanges = exchanges
    self.savedAt = savedAt
  }

  /// A question about the place and Loci's answer.
  public struct Exchange: Hashable, Sendable {
    public let question: String
    public let answer: String
    public let askedAt: Timestamp

    public init(question: String, answer: String, askedAt: Timestamp) throws {
      self.question = try question.requiringText("question")
      self.answer = try answer.requiringText("answer")
      self.askedAt = askedAt
    }
  }

  /// The notes as they stand after every entry, in the order they were first saved.
  ///
  /// A later version replaces an earlier one; a deleted note stays deleted even if its id is saved again.
  public static func current(in entries: some Sequence<NoteEntry>) -> [Note] {
    var order: [EntityID] = []
    var latest: [EntityID: Note] = [:]
    var deleted: Set<EntityID> = []
    for entry in entries {
      switch entry {
      case .saved(let note) where !deleted.contains(note.id):
        if latest.updateValue(note, forKey: note.id) == nil { order.append(note.id) }
      case .saved:
        continue
      case .deleted(let id, _):
        deleted.insert(id)
        latest[id] = nil
      }
    }
    return order.compactMap { latest[$0] }
  }
}

/// One line of `notes/<content id>.jsonl`. The file is only appended to, so editing a note saves it again
/// and deleting one appends a deletion.
public enum NoteEntry: Hashable, Sendable {
  case saved(Note)
  case deleted(EntityID, at: Timestamp)
}

extension NoteEntry: Codable {
  private enum CodingKeys: String, CodingKey {
    case event, id, locator, excerpt, thought, exchanges, savedAt, at
  }

  private enum Event: String, Codable {
    case saved, deleted
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(EntityID.self, forKey: .id)
    switch try container.decode(Event.self, forKey: .event) {
    case .deleted:
      self = .deleted(id, at: try container.decode(Timestamp.self, forKey: .at))
    case .saved:
      let locator = try container.decode(Locator.self, forKey: .locator)
      let excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
      let thought = try container.decodeIfPresent(String.self, forKey: .thought)
      let exchanges = try container.decodeIfPresent([Note.Exchange].self, forKey: .exchanges) ?? []
      let savedAt = try container.decode(Timestamp.self, forKey: .savedAt)
      self = .saved(
        try decoder.validated {
          try Note(
            id: id, locator: locator, excerpt: excerpt, thought: thought, exchanges: exchanges, savedAt: savedAt)
        })
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .deleted(let id, let at):
      try container.encode(Event.deleted, forKey: .event)
      try container.encode(id, forKey: .id)
      try container.encode(at, forKey: .at)
    case .saved(let note):
      try container.encode(Event.saved, forKey: .event)
      try container.encode(note.id, forKey: .id)
      try container.encode(note.locator, forKey: .locator)
      try container.encodeIfPresent(note.excerpt, forKey: .excerpt)
      try container.encodeIfPresent(note.thought, forKey: .thought)
      if !note.exchanges.isEmpty { try container.encode(note.exchanges, forKey: .exchanges) }
      try container.encode(note.savedAt, forKey: .savedAt)
    }
  }
}

extension Note.Exchange: Codable {
  private enum CodingKeys: String, CodingKey {
    case question, answer, askedAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let question = try container.decode(String.self, forKey: .question)
    let answer = try container.decode(String.self, forKey: .answer)
    let askedAt = try container.decode(Timestamp.self, forKey: .askedAt)
    self = try decoder.validated {
      try Note.Exchange(question: question, answer: answer, askedAt: askedAt)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(question, forKey: .question)
    try container.encode(answer, forKey: .answer)
    try container.encode(askedAt, forKey: .askedAt)
  }
}

/// A note on the wire has the same shape as the line that saved it.
extension Note: Codable {
  public init(from decoder: any Decoder) throws {
    guard case .saved(let note) = try NoteEntry(from: decoder) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "a deletion, not a note"))
    }
    self = note
  }

  public func encode(to encoder: any Encoder) throws {
    try NoteEntry.saved(self).encode(to: encoder)
  }
}
