/// Adds a text file to the library. The title is `title` when given, else the first `# ` heading, else the
/// file's name.
public struct AddTextItem: Command {
  public static let name = "item.addText"
  public let fileName: String
  public let text: String
  public let title: String?
  /// Who wrote it; empty when not known.
  public let authors: [String]

  public init(fileName: String, text: String, title: String? = nil, authors: [String] = []) {
    self.fileName = fileName
    self.text = text
    self.title = title
    self.authors = authors
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    fileName = try container.decode(String.self, forKey: .fileName)
    text = try container.decode(String.self, forKey: .text)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Item {
    try await handler.addTextItem(self)
  }
}

public struct DeleteItem: Command {
  public static let name = "item.delete"
  public let item: EntityID
  public let notes: NotesOnDelete

  public init(item: EntityID, notes: NotesOnDelete) {
    self.item = item
    self.notes = notes
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteItem(self)
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
