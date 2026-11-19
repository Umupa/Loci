import Foundation

/// One request from the `loci` command to the app on this Mac, through the socket in the data folder.
/// Commands and subscriptions travel by their wire names and JSON, as they do between Macs.
public struct LocalCall: Hashable, Codable, Sendable {
  /// The variable that tells the `loci` command where the app's socket is.
  public static let socketVariable = "LOCI_SOCKET"
  /// The variable that holds the `loci` program's full path, for a PATH where `loci` is another program.
  public static let commandVariable = "LOCI"
  /// The variable that tells the `loci` command which conversation its agent is in, as a note tag.
  public static let sessionVariable = "LOCI_SESSION"

  /// The conversation the agent that ran the command is in; `nil` outside one, such as the daily review.
  public let conversation: ConversationRef?
  public let request: Request

  public init(conversation: ConversationRef?, request: Request) {
    self.conversation = conversation
    self.request = request
  }

  public enum Request: Hashable, Codable, Sendable {
    /// A command by its wire name, with its JSON. The reply is one value.
    case command(name: String, body: Data)
    /// A subscription by its wire name, with its JSON. The replies are its feeds, until the caller hangs up.
    case follow(name: String, body: Data)
    /// Makes a file on this Mac available to the commands, as `Host.upload` does. The reply is an `Upload`.
    case upload(path: String)
    /// Where an item's folder is, relative to Loci's `agent` folder. The reply is a `String`.
    case itemFolder(EntityID)
  }
}

/// What the app answers a `LocalCall` with, once or, for a subscription, many times.
public enum LocalReply: Hashable, Codable, Sendable {
  /// A command's reply, a feed, an upload or a path, as JSON.
  case value(Data)
  case failed(HostError)
}

extension ConversationRef {
  /// The tag the conversation's notes carry: `main` or `library/<item id>`.
  public var tag: String {
    switch self {
    case .main: NoteSource.main.tag
    case .item(let item): NoteSource.item(item, title: nil).tag
    }
  }

  /// The conversation a note tag names; `nil` for the review's tag or anything else.
  public init?(tag: String) {
    switch NoteSource(tag: tag, title: { _ in nil }) {
    case .main: self = .main
    case .item(let item, _): self = .item(item)
    case .review, nil: return nil
    }
  }
}
