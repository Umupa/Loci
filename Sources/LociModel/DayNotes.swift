/// One day's notes, `notes/<day>.md`: what any session wrote down that day, in the order written.
public struct DayNotes: Hashable, Codable, Sendable {
  public let day: Day
  public let notes: [Line<DayNote>]

  public init(day: Day, notes: [Line<DayNote>]) {
    self.day = day
    self.notes = notes
  }

  /// Reads the file of `day`. `title` names an item in the library, or gives `nil` for one that is gone.
  public init(day: Day, parsing text: String, title: (EntityID) -> String?) {
    self.day = day
    notes = Bullets.pieces(of: text).map { piece in
      switch piece {
      case .other(let line):
        return .text(line)
      case .item(let line, let text):
        guard let note = DayNote(parsing: text, title: title) else { return .text(line) }
        return .entry(note)
      }
    }
  }
}

/// One note: `- HH:MM [where] text`, the time and the place both optional.
public struct DayNote: Hashable, Codable, Sendable {
  public let time: TimeOfDay?
  public let text: String
  public let from: NoteSource?

  public init(time: TimeOfDay?, text: String, from: NoteSource?) {
    self.time = time
    self.text = text
    self.from = from
  }

  init?(parsing text: String, title: (EntityID) -> String?) {
    var rest = Substring(text)
    var time: TimeOfDay?
    if let match = rest.prefixMatch(of: /(\d{1,2}:\d\d)(\s+|$)/), let parsed = TimeOfDay(String(match.1)) {
      time = parsed
      rest = rest[match.range.upperBound...]
    }
    var from: NoteSource?
    if let match = rest.prefixMatch(of: /\[([^\]]+)\]\s*/), let source = NoteSource(tag: String(match.1), title: title)
    {
      from = source
      rest = rest[match.range.upperBound...]
    }
    let words = rest.trimmingCharacters(in: .whitespaces)
    guard !words.isEmpty else { return nil }
    self.init(time: time, text: words, from: from)
  }
}

/// Which conversation a note came from.
public enum NoteSource: Hashable, Codable, Sendable {
  case main
  /// The item's conversation, with the item's title; `nil` when the item is gone.
  case item(EntityID, title: String?)
  case course(EntityID)
  /// The daily review.
  case review
  /// A run in the background.
  case run(EntityID)

  /// The tag a session writes in its daily notes.
  public var tag: String {
    switch self {
    case .main: "main"
    case .item(let item, _): "library/\(item)"
    case .course(let course): "courses/\(course)"
    case .review: "review"
    case .run(let run): "run/\(run)"
    }
  }

  init?(tag: String, title: (EntityID) -> String?) {
    switch tag {
    case "main": self = .main
    case "review": self = .review
    case _ where tag.hasPrefix("library/"):
      guard let item = EntityID(canonical: String(tag.dropFirst(8))) else { return nil }
      self = .item(item, title: title(item))
    case _ where tag.hasPrefix("run/"):
      guard let run = EntityID(canonical: String(tag.dropFirst(4))) else { return nil }
      self = .run(run)
    case _ where tag.hasPrefix("courses/"):
      guard let course = EntityID(canonical: String(tag.dropFirst(8))) else { return nil }
      self = .course(course)
    default: return nil
    }
  }
}
