import Foundation

public struct Lesson: Hashable, Codable, Sendable, Identifiable {
  public struct ID: Hashable, Sendable, TextCodable {
    public let description: String

    public init?(_ description: String) {
      let bytes = description.utf8
      guard (1...64).contains(bytes.count), let first = bytes.first, let last = bytes.last,
        Self.isLetterOrDigit(first), Self.isLetterOrDigit(last),
        bytes.allSatisfy({ Self.isLetterOrDigit($0) || $0 == 45 })
      else { return nil }
      self.description = description
    }

    private static func isLetterOrDigit(_ byte: UInt8) -> Bool {
      (97...122).contains(byte) || (48...57).contains(byte)
    }
  }

  public let id: ID
  public let title: String

  public init(id: ID, title: String) throws {
    self.id = id
    self.title = try CourseGoal.line(title, field: "lesson title")
  }

  private enum CodingKeys: String, CodingKey {
    case id, title
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self = try decoder.validated {
      try Lesson(id: values.decode(ID.self, forKey: .id), title: values.decode(String.self, forKey: .title))
    }
  }
}
