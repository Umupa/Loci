import Foundation

public struct CourseGoal: Hashable, Codable, Sendable {
  public enum Field: String, Hashable, Codable, Sendable {
    case title, subtitle, purpose, focus, known, depth, length
  }

  public let title: String?
  public let subtitle: String?
  public let purpose: String?
  public let focus: String?
  public let known: String?
  public let depth: String?
  public let length: String?

  public init(
    title: String? = nil, subtitle: String? = nil, purpose: String? = nil, focus: String? = nil,
    known: String? = nil, depth: String? = nil, length: String? = nil
  ) throws {
    self.title = try title.map { try Self.line($0, field: "title") }
    self.subtitle = try subtitle.map { try Self.line($0, field: "subtitle") }
    self.purpose = try purpose.map { try Self.line($0, field: "purpose") }
    self.focus = try focus.map { try Self.line($0, field: "focus") }
    self.known = try known.map { try Self.line($0, field: "known") }
    self.depth = try depth.map { try Self.line($0, field: "depth") }
    self.length = try length.map { try Self.line($0, field: "length") }
  }

  private enum CodingKeys: String, CodingKey {
    case title, subtitle, purpose, focus, known, depth, length
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self = try decoder.validated {
      try CourseGoal(
        title: values.decodeIfPresent(String.self, forKey: .title),
        subtitle: values.decodeIfPresent(String.self, forKey: .subtitle),
        purpose: values.decodeIfPresent(String.self, forKey: .purpose),
        focus: values.decodeIfPresent(String.self, forKey: .focus),
        known: values.decodeIfPresent(String.self, forKey: .known),
        depth: values.decodeIfPresent(String.self, forKey: .depth),
        length: values.decodeIfPresent(String.self, forKey: .length))
    }
  }

  static func line(_ text: String, field: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else {
      throw ModelError("\(field) must be one line of text")
    }
    return trimmed
  }

  func applying(_ changes: CourseGoal) throws -> CourseGoal {
    try CourseGoal(
      title: changes.title ?? title, subtitle: changes.subtitle ?? subtitle, purpose: changes.purpose ?? purpose,
      focus: changes.focus ?? focus, known: changes.known ?? known, depth: changes.depth ?? depth,
      length: changes.length ?? length)
  }
}
