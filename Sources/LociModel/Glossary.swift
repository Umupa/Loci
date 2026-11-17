import Foundation

/// The terms a mentor's lessons introduce, each with a one-line definition; the contents of `glossary.yaml`.
///
/// ```yaml
/// terms:
/// - term: watch
///   aliases: [watches]
///   definition: A client's subscription to changes of one kind of object.
///   lesson: watch-and-list
/// ```
public struct Glossary: Hashable, Sendable {
  public let terms: [Term]

  public init(terms: [Term]) throws {
    var seen = Set<String>()
    for name in terms.flatMap(\.names) where !seen.insert(name.lowercased()).inserted {
      throw ModelError("\(name) is in the glossary twice")
    }
    self.terms = terms
  }

  public static let empty = Glossary(unchecked: [])

  private init(unchecked terms: [Term]) {
    self.terms = terms
  }

  public struct Term: Hashable, Sendable {
    public let term: String
    /// Other spellings that count as the same term, such as a plural.
    public let aliases: [String]
    public let definition: String
    /// The lesson that teaches the term.
    public let lesson: Lesson.Slug?

    public init(term: String, aliases: [String] = [], definition: String, lesson: Lesson.Slug? = nil) throws {
      self.term = try term.trimmingCharacters(in: .whitespaces).requiringText("term")
      self.aliases = try aliases.map { try $0.trimmingCharacters(in: .whitespaces).requiringText("alias") }
      self.definition = try definition.trimmingCharacters(in: .whitespacesAndNewlines).requiringText("definition")
      guard !self.definition.contains("\n") else { throw ModelError("the definition of \(term) is not one line") }
      self.lesson = lesson
    }

    var names: [String] { [term] + aliases }
  }

  /// Where a term is used in a text.
  public struct Use: Hashable, Sendable {
    public let term: Term
    public let range: Range<String.Index>
  }

  /// The first use of each term in `text`, by its name or an alias, ignoring case, in the order they appear.
  ///
  /// The lesson that teaches a term does not mark it. A Latin name matches only whole words, so "pod" is
  /// not found inside "tripod"; names in Chinese match anywhere.
  public func firstUses(in text: String, in lesson: Lesson.Slug? = nil) -> [Use] {
    var uses: [Use] = []
    for term in terms where term.lesson == nil || term.lesson != lesson {
      let found = term.names.compactMap { Self.firstWord($0, in: text) }.min { $0.lowerBound < $1.lowerBound }
      if let found, !uses.contains(where: { $0.range.overlaps(found) }) {
        uses.append(Use(term: term, range: found))
      }
    }
    return uses.sorted { $0.range.lowerBound < $1.range.lowerBound }
  }

  private static func firstWord(_ name: String, in text: String) -> Range<String.Index>? {
    var start = text.startIndex
    while let found = text.range(of: name, options: [.caseInsensitive], range: start..<text.endIndex) {
      if isWhole(found, in: text) { return found }
      start = found.upperBound
    }
    return nil
  }

  private static func isWhole(_ range: Range<String.Index>, in text: String) -> Bool {
    func isLatinWord(_ character: Character?) -> Bool {
      guard let character, character.isASCII else { return false }
      return character.isLetter || character.isNumber
    }
    let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
    let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
    let first = text[range.lowerBound]
    let last = text[text.index(before: range.upperBound)]
    return !(isLatinWord(first) && isLatinWord(before)) && !(isLatinWord(last) && isLatinWord(after))
  }
}

extension Glossary: Codable {
  private enum CodingKeys: String, CodingKey {
    case terms
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let terms = try container.decodeIfPresent([Term].self, forKey: .terms) ?? []
    self = try decoder.validated { try Glossary(terms: terms) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(terms, forKey: .terms)
  }
}

extension Glossary.Term: Codable {
  private enum CodingKeys: String, CodingKey {
    case term, aliases, definition, lesson
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let term = try container.decode(String.self, forKey: .term)
    let aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    let definition = try container.decode(String.self, forKey: .definition)
    let lesson = try container.decodeIfPresent(Lesson.Slug.self, forKey: .lesson)
    self = try decoder.validated {
      try Glossary.Term(term: term, aliases: aliases, definition: definition, lesson: lesson)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(term, forKey: .term)
    if !aliases.isEmpty { try container.encode(aliases, forKey: .aliases) }
    try container.encode(definition, forKey: .definition)
    try container.encodeIfPresent(lesson, forKey: .lesson)
  }
}
