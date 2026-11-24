import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func importBook(_ command: ImportBook) async throws(HostError) -> Item {
    guard let file = await hub.takeUpload(command.upload.id) else { throw .notFound("upload \(command.upload.id)") }
    let book: BookImport
    do {
      book = try Store.readBook(file)
    } catch {
      throw .unsupportedBook(error)
    }
    let item = try attempt {
      try Item(id: environment.newID(), kind: .book, title: book.title, authors: book.authors, language: book.language)
    }
    try attempt { try store.addBook(item, copying: file, as: book) }
    await follow([.item(item.id)])
    await saved(item.id, by: .person)
    return item
  }

  public func bookContents(of item: EntityID) async throws(HostError) -> BookContents {
    try attempt { try store.bookContents(of: item) }
  }

  public func bookFile(_ command: ReadBookFile) async throws(HostError) -> Data {
    try attempt { try store.bookFile(command.path, of: command.item) }
  }
}
