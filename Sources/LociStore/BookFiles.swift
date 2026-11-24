import Foundation
import LociModel

/// A file read as a book, before it is kept: what to call it and its cover.
public struct BookImport: Sendable {
  public let title: String
  public let authors: [String]
  public let language: String?
  public let cover: (data: Data, pathExtension: String)?
  public let format: BookFormat
}

/// How a book is kept in its folder: an EPUB as it came, or the text file's bytes as they came.
public enum BookFormat: String, Sendable {
  case epub
  case text

  var fileName: String {
    switch self {
    case .epub: "book.epub"
    case .text: "book.txt"
    }
  }
}

extension Store {
  /// Reads a file as a book, from its extension: `.epub` or `.txt`. Throws the reason it cannot be one.
  public static func readBook(_ file: URL) throws(BookProblem) -> BookImport {
    let name = file.deletingPathExtension().lastPathComponent
    switch file.pathExtension.lowercased() {
    case "epub":
      let archive: BookArchive
      do {
        archive = try BookArchive(file)
      } catch {
        throw .damaged
      }
      let package = try EPUBPackage(archive)
      let cover = package.cover.flatMap { path in
        (try? archive.file(path)).map { ($0, (path as NSString).pathExtension.lowercased()) }
      }
      return BookImport(
        title: package.title ?? name, authors: package.authors, language: package.language, cover: cover,
        format: .epub)
    case "txt":
      guard let data = try? Data(contentsOf: file) else { throw .damaged }
      let book = try TextBook(data, title: name)
      return BookImport(title: name, authors: [], language: book.language, cover: nil, format: .text)
    default:
      throw .notABook
    }
  }

  /// Makes the book's folder: its `item.json`, the file copied in as it is, and its cover. Nothing stays behind
  /// when one of them cannot be written.
  public func addBook(_ item: Item, copying file: URL, as book: BookImport) throws {
    guard !folderExists(holding: item.id, in: libraryFolder, file: Self.itemFile) else {
      throw StoreError.alreadyExists(item.id)
    }
    let folder = libraryFolder.appending(path: FolderName.make(for: item.title, id: item.id))
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: file, to: folder.appending(path: book.format.fileName))
      if let cover = book.cover, !cover.pathExtension.isEmpty {
        try write(cover.data, to: folder.appending(path: "\(Self.coverName).\(cover.pathExtension)"))
      }
      try write(Formats.document(item), to: folder.appending(path: Self.itemFile))
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }

  public func bookContents(of item: EntityID) throws -> BookContents {
    switch try bookSource(of: item) {
    case .epub(let archive):
      do {
        let package = try EPUBPackage(archive)
        return BookContents(chapters: package.chapters, toc: package.toc, language: package.language)
      } catch {
        throw StoreError.invalid(FileProblem(path: "book.epub", kind: .invalid, reason: error.rawValue))
      }
    case .text(let book): return book.contents
    }
  }

  /// A file inside the book by its path from the book's root; for a text book, a chapter's page.
  public func bookFile(_ path: String, of item: EntityID) throws -> Data {
    switch try bookSource(of: item) {
    case .epub(let archive):
      do {
        return try archive.file(path)
      } catch BookArchive.Failure.missing {
        throw StoreError.notFound(path)
      }
    case .text(let book):
      guard let chapter = TextBook.chapter(in: path), book.chapters.indices.contains(chapter) else {
        throw StoreError.notFound(path)
      }
      return book.page(chapter)
    }
  }

  private enum BookSource {
    case epub(BookArchive)
    case text(TextBook)
  }

  private func bookSource(of item: EntityID) throws -> BookSource {
    let folder = try itemFolder(item)
    let epub = folder.appending(path: BookFormat.epub.fileName)
    if FileManager.default.fileExists(atPath: epub.path(percentEncoded: false)) {
      return .epub(try BookArchive(epub))
    }
    let text = folder.appending(path: BookFormat.text.fileName)
    let title = try self.item(item).title
    do {
      return .text(try TextBook(try read(text), title: title))
    } catch let problem as BookProblem {
      throw StoreError.invalid(FileProblem(path: relativePath(of: text), kind: .unreadable, reason: problem.rawValue))
    }
  }
}
