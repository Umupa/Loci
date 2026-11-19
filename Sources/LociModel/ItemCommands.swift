/// Adds a text file to the library. The title is the first `# ` heading, or else the file's name.
public struct AddTextItem: Command {
  public static let name = "item.addText"
  public let fileName: String
  public let text: String

  public init(fileName: String, text: String) {
    self.fileName = fileName
    self.text = text
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Item {
    try await handler.addTextItem(self)
  }
}

/// Takes items out of the library with their highlights and conversations. They can be brought back with
/// `RestoreDeleted` until the next deletion, or until the app quits.
public struct DeleteItems: Command {
  public static let name = "item.delete"
  public let items: [EntityID]

  public init(_ items: [EntityID]) {
    self.items = items
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteItems(self)
  }
}

/// Brings back what the last `DeleteItems` took out, as it was. Returns what came back; nothing when that
/// deletion can no longer be undone.
public struct RestoreDeleted: Command {
  public static let name = "item.restoreDeleted"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [Item] {
    try await handler.restoreDeleted()
  }
}

public struct RenameItem: Command {
  public static let name = "item.rename"
  public let item: EntityID
  public let title: String

  public init(item: EntityID, title: String) {
    self.item = item
    self.title = title
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Item {
    try await handler.renameItem(self)
  }
}

/// Replaces an item's cover with an uploaded picture.
public struct SetCover: Command {
  public static let name = "item.setCover"
  /// The picture formats a cover may be in, by file extension: the ones Loci keeps for its own face.
  public static let formats = Avatar.formats
  public let item: EntityID
  public let upload: Upload

  public init(item: EntityID, upload: Upload) {
    self.item = item
    self.upload = upload
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.setCover(self)
  }
}

public struct ListItems: Command {
  public static let name = "item.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [Item] {
    try await handler.listItems()
  }
}

public struct ReadItemText: Command {
  public static let name = "item.text"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> String {
    try await handler.itemText(item)
  }
}
