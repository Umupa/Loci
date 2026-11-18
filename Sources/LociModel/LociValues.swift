import Foundation

/// A line of a file Loci and the person both write: one that parsed, or one shown as it is.
public enum Line<Entry: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
  case entry(Entry)
  case text(String)
}

/// What the Loci page shows.
public struct LociPage: Hashable, Codable, Sendable {
  public let soul: Soul
  /// `MEMORY.md`, in file order.
  public let memory: [Line<MemoryEntry>]
  /// `USER.md`, in file order.
  public let profile: [Line<MemoryEntry>]
  /// Today's `notes/<day>.md`.
  public let today: DayNotes
  /// Days with a diary, newest first.
  public let diaries: [Diary.Heading]
  public let together: Together

  public init(
    soul: Soul, memory: [Line<MemoryEntry>], profile: [Line<MemoryEntry>], today: DayNotes,
    diaries: [Diary.Heading], together: Together
  ) {
    self.soul = soul
    self.memory = memory
    self.profile = profile
    self.today = today
    self.diaries = diaries
    self.together = together
  }
}

/// How long and how much the person and Loci have been at it.
public struct Together: Hashable, Codable, Sendable {
  /// From the day of the first message to today, both counted; 0 before any.
  public let days: Int
  /// Messages the person sent, in every conversation.
  public let messages: Int
  /// Items whose conversation has at least one message.
  public let itemsReadTogether: Int

  public init(days: Int, messages: Int, itemsReadTogether: Int) {
    self.days = days
    self.messages = messages
    self.itemsReadTogether = itemsReadTogether
  }
}

/// Whether Loci is working on anything: a turn in any conversation, or the daily review.
public struct LociStatus: Hashable, Codable, Sendable {
  public let working: Bool

  public init(working: Bool) {
    self.working = working
  }
}

/// A picture the person chose to show as Loci.
public struct Avatar: Hashable, Codable, Sendable {
  public let data: Data
  /// The file extension it is kept under: one of `formats`.
  public let format: String

  public static let formats: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff"]
  public static let largest = 10 * 1024 * 1024

  public init(data: Data, format: String) throws {
    let format = format.lowercased()
    guard Self.formats.contains(format) else { throw ModelError("\(format) is not a picture format Loci keeps") }
    guard !data.isEmpty, data.count <= Self.largest else { throw ModelError("the picture is empty or over 10 MB") }
    self.data = data
    self.format = format
  }
}

extension Avatar {
  private enum CodingKeys: String, CodingKey {
    case data, format
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let data = try container.decode(Data.self, forKey: .data)
    let format = try container.decode(String.self, forKey: .format)
    self = try decoder.validated { try Avatar(data: data, format: format) }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(data, forKey: .data)
    try container.encode(format, forKey: .format)
  }
}

/// The two files of things remembered that the person can prune.
public enum MemoryFile: String, Hashable, Codable, Sendable {
  /// `MEMORY.md`.
  case memory
  /// `USER.md`.
  case profile
}
