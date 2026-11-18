import Foundation

/// A file or folder on this Mac, for handing to the system here: open, reveal, play.
///
/// It is deliberately not `Codable`, so no command, subscription or reply can carry it to another Mac.
public struct LocalFile: Hashable, Sendable {
  public let url: URL

  public init(_ url: URL) {
    self.url = url
  }
}

/// A path on the host's Mac, to show. It opens nothing here.
public struct HostPath: Hashable, Codable, Sendable, CustomStringConvertible {
  public let text: String

  public init(_ url: URL) {
    text = url.path(percentEncoded: false)
  }

  public var description: String { text }
}

/// Things on the host's Mac the interface can hand to the system, when the host is this Mac.
public enum LocalPlace: Hashable, Sendable {
  case dataFolder
  /// Loci's `agent` folder: its Soul, memory, notes and diary.
  case agentFolder
  /// The downloaded or imported media of a video or audio item.
  case media(EntityID)
}

/// A file made available to the host before a command uses it. A remote host has received its bytes.
public struct Upload: Hashable, Codable, Sendable {
  public let id: EntityID

  public init(id: EntityID) {
    self.id = id
  }
}
