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
  /// `nil` from a Mac that keeps no feelings.
  public let feeling: Feeling?

  public init(
    soul: Soul, memory: [Line<MemoryEntry>], profile: [Line<MemoryEntry>], today: DayNotes,
    diaries: [Diary.Heading], together: Together, feeling: Feeling? = nil
  ) {
    self.soul = soul
    self.memory = memory
    self.profile = profile
    self.today = today
    self.diaries = diaries
    self.together = together
    self.feeling = feeling
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

/// How the companion is when it is not busy: how tired, and what it said last in the main conversation.
public struct LociPresence: Hashable, Codable, Sendable {
  public let tiredness: Tiredness
  /// The text of its latest reply in the main conversation; `nil` before it said anything there.
  public let lastSaid: String?

  public init(tiredness: Tiredness, lastSaid: String?) {
    self.tiredness = tiredness
    self.lastSaid = lastSaid
  }
}

/// What Loci is working on, if anything.
public struct LociStatus: Hashable, Codable, Sendable {
  /// `nil` while Loci is idle.
  public let work: LociWork?

  public init(work: LociWork?) {
    self.work = work
  }

  public var working: Bool { work != nil }
}

extension LociStatus {
  private enum CodingKeys: String, CodingKey {
    case work, working
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let work = try container.decodeIfPresent(LociWork.self, forKey: .work) {
      self.init(work: work)
    } else {
      self.init(work: try container.decodeIfPresent(Bool.self, forKey: .working) == true ? .unspecified : nil)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(working, forKey: .working)
    try container.encodeIfPresent(work, forKey: .work)
  }
}

/// One thing Loci can be busy with. When it does several at once, the status names the one the person is
/// most likely waiting on.
public enum LociWork: Hashable, Codable, Sendable {
  /// An older Mac reports that Loci is busy without saying what it is doing.
  case unspecified
  /// Answering in a conversation, with the tool it used last; `nil` while it has used none.
  case answering(ToolActivity?)
  /// Refreshing the panel with this title.
  case refreshing(title: String)
  /// Looking back on a day.
  case reviewing
  /// Doing what a schedule or a follow-up with this title is for.
  case looking(title: String)
  /// Taking in items it saved.
  case saving
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
