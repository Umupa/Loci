import Foundation

/// Adds an EPUB or text file on the host to the library as a book. Nothing is added when it cannot be read as one.
public struct ImportBook: RemoteCommand {
  public static let name = "library.importBook"
  public let upload: Upload

  public init(upload: Upload) {
    self.upload = upload
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Item {
    try await handler.importBook(self)
  }
}

/// A book's chapters and table of contents.
public struct ReadBookContents: RemoteCommand {
  public static let name = "book.contents"
  public let item: EntityID

  public init(item: EntityID) {
    self.item = item
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> BookContents {
    try await handler.bookContents(of: item)
  }
}

/// One file inside a book, by its path from the book's root: a chapter, a style sheet or a picture.
public struct ReadBookFile: RemoteCommand {
  public static let name = "book.file"
  public let item: EntityID
  public let path: String

  public init(item: EntityID, path: String) {
    self.item = item
    self.path = path
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Data {
    try await handler.bookFile(self)
  }
}
