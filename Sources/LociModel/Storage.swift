/// How much room Loci's media takes on the host, and on what.
public struct StorageReport: Hashable, Codable, Sendable {
  /// The size of the disk the data folder is on, and how much of it is free; `nil` when it cannot be told.
  public let capacity: Int64?
  public let available: Int64?
  /// Every video and episode, newest first.
  public let items: [ItemSpace]
  /// Every speech model on the disk.
  public let speechModels: [ModelSpace]

  public let sourceCacheBytes: Int64?

  public init(
    capacity: Int64?, available: Int64?, items: [ItemSpace], speechModels: [ModelSpace],
    sourceCacheBytes: Int64? = nil
  ) {
    self.capacity = capacity
    self.available = available
    self.items = items
    self.speechModels = speechModels
    self.sourceCacheBytes = sourceCacheBytes
  }

  /// What the media of `kind` and the speech models take, together.
  public func bytes(of kind: Item.Kind? = nil) -> Int64 {
    items.filter { kind == nil || $0.isAudio == (kind.map { if case .audio = $0 { true } else { false } } ?? false) }
      .compactMap(\.bytes).reduce(0, +)
  }

  public var modelBytes: Int64 {
    speechModels.map(\.bytes).reduce(0, +)
  }
}

/// A video's or episode's media on the host.
public struct ItemSpace: Hashable, Codable, Sendable {
  public let item: EntityID
  public let isAudio: Bool
  /// `nil` when there is no file on the host and it plays online.
  public let bytes: Int64?
  /// It came from a link, so it can play online once its file is gone, and be downloaded again.
  public let fromLink: Bool

  public init(item: EntityID, isAudio: Bool, bytes: Int64?, fromLink: Bool) {
    self.item = item
    self.isAudio = isAudio
    self.bytes = bytes
    self.fromLink = fromLink
  }
}

public struct ModelSpace: Hashable, Codable, Sendable {
  public let model: SpeechModel
  public let bytes: Int64

  public init(model: SpeechModel, bytes: Int64) {
    self.model = model
    self.bytes = bytes
  }
}

/// The room Loci's media takes.
public struct StorageUse: Subscription {
  public static let name = "media.storage"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> StorageReport {
    try await handler.storage()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .item, .media, .everything: true
      case .course, .courseActivity, .notes, .reading, .job, .conversation, .turnEnded, .review, .loci,
        .runtime, .timers, .connectors:
        false
      }
    }
  }
}

/// Deletes a video's or episode's media file and keeps it as watched online from then on; its transcript,
/// translations, notes, chapters and highlights stay. Only for an item that came from a link.
public struct FreeMediaSpace: RemoteCommand {
  public static let name = "media.free"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.freeMediaSpace(item)
  }
}

/// Keeps a video or episode watched online on this Mac from then on, and downloads its media.
public struct SaveMediaLocally: RemoteCommand {
  public static let name = "media.saveLocally"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Job {
    try await handler.saveMediaLocally(item)
  }
}
