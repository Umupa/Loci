import Foundation

/// Adds the material behind a link to the library and starts making it readable. The item is there at once,
/// titled after the link until its real title is known; its job does the rest. A link probed a moment ago
/// with `ProbeLink` is not read again.
public struct AddLink: RemoteCommand {
  public static let name = "library.addLink"
  public static let maximumArticleBytes = 2 * 1024 * 1024
  public let url: URL
  /// The article already open in the built-in browser.
  public let articleHTML: String?
  /// How a video or episode is taken in, and the next default; `nil` takes the last choice.
  public let choice: ImportChoice?
  /// Why the reader takes it in.
  public let why: String?

  public init(url: URL, articleHTML: String? = nil, choice: ImportChoice? = nil, why: String? = nil) {
    self.url = url
    self.articleHTML = articleHTML
    self.choice = choice
    self.why = why
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Item {
    try await handler.addLink(self)
  }
}

/// Adds a video or audio file on the host to the library, and starts recognizing what is said in it.
public struct ImportMediaFile: RemoteCommand {
  public static let name = "library.importMedia"
  public let upload: Upload
  public let mode: ImportMode
  /// How speech in it is recognized and translated, and the next default; `nil` takes the last choice.
  public let choice: ImportChoice?
  /// Why the reader takes it in.
  public let why: String?

  public init(upload: Upload, mode: ImportMode, choice: ImportChoice? = nil, why: String? = nil) {
    self.upload = upload
    self.mode = mode
    self.choice = choice
    self.why = why
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Item {
    try await handler.importMediaFile(self)
  }
}

/// Starts an item's job again from what its files already hold: after a failure, after it was paused, or
/// to stop waiting and look again.
public struct RetryJob: RemoteCommand {
  public static let name = "library.retryJob"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Job {
    try await handler.retryJob(item)
  }
}

/// Pauses an item's job. What it made so far is kept, a download's part among it, and `RetryJob` carries on
/// from there.
public struct PauseJob: RemoteCommand {
  public static let name = "library.pauseJob"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.pauseJob(item)
  }
}

/// Translates an article into the reader's language, passage by passage, keeping what was translated before.
/// The page shows each passage as it arrives.
public struct TranslateArticle: RemoteCommand {
  public static let name = "library.translateArticle"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.translateArticle(item)
  }
}

/// Where a video or audio item plays from now. `refresh` asks the site for a new address, for when the
/// one given before has stopped working.
public struct ReadPlayback: RemoteCommand {
  public static let name = "library.playback"
  public let item: EntityID
  public let refresh: Bool

  public init(item: EntityID, refresh: Bool = false) {
    self.item = item
    self.refresh = refresh
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Playback {
    try await handler.playback(self)
  }
}

/// The item's cover picture; `nil` when it has none.
public struct ReadCover: RemoteCommand {
  public static let name = "item.cover"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Data? {
    try await handler.cover(of: item)
  }
}

/// A paper's PDF.
public struct ReadItemPDF: RemoteCommand {
  public static let name = "item.pdf"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Data {
    try await handler.itemPDF(item)
  }
}

/// A picture in an article, by the name its text refers to it with: `images/<name>` or just `<name>`.
public struct ReadItemImage: RemoteCommand {
  public static let name = "item.image"
  public let item: EntityID
  public let name: String

  public init(item: EntityID, name: String) {
    self.item = item
    self.name = name
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Data {
    try await handler.itemImage(self)
  }
}

/// Every job that is not done, oldest first.
public struct ListJobs: RemoteCommand {
  public static let name = "library.jobs"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [Job] {
    try await handler.jobs()
  }
}

/// What a video or audio item shows beside its player, once; `ItemMedia` keeps it current.
public struct ReadMediaPage: RemoteCommand {
  public static let name = "item.media"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> MediaPage {
    try await handler.mediaPage(item)
  }
}
