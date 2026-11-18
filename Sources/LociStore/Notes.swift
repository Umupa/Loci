import Foundation
import LociModel

extension Store {
  static let libraryNotesFolder = "library"

  /// `notes/library/<item id>.jsonl`.
  func notesFile(on content: ContentRef) -> URL {
    switch content {
    case .item(let item): notesFolder.appending(path: Self.libraryNotesFolder).appending(path: "\(item).jsonl")
    }
  }

  /// The notes as they stand now. Lines that cannot be read, or that point into other content, are
  /// skipped and reported; the other lines still count.
  public func notes(on content: ContentRef) -> Loaded<[Note]> {
    let url = notesFile(on: content)
    let path = relativePath(of: url)
    let text: String
    do {
      text = try readText(url)
    } catch StoreError.notFound {
      return Loaded(value: [], problems: [])
    } catch {
      return Loaded(value: [], problems: [problem(at: url, error).attributed(to: .notes(content))])
    }
    var entries: [NoteEntry] = []
    var problems: [FileProblem] = []
    for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
    where !line.trimmingCharacters(in: .whitespaces).isEmpty {
      do {
        let entry = try JSONDecoder().decode(NoteEntry.self, from: Data(line.utf8))
        if case .saved(let note) = entry, note.locator.content != content {
          problems.append(
            FileProblem(
              path: path, kind: .misplacedNote, reason: "line \(index + 1): \(note.locator) is not on this content"))
        } else {
          entries.append(entry)
        }
      } catch {
        problems.append(FileProblem(path: path, kind: .invalid, reason: "line \(index + 1): \(Formats.reason(error))"))
      }
    }
    return Loaded(value: Note.current(in: entries), problems: problems.map { $0.attributed(to: .notes(content)) })
  }

  /// Adds one line to the content's notes file. The file is only ever appended to.
  ///
  /// The line goes out in a single append, so another writer's line cannot land inside it. If the file
  /// ends in a line cut short by a crash, the new line starts on a line of its own.
  public func append(_ entry: NoteEntry, on content: ContentRef) throws {
    if case .saved(let note) = entry, note.locator.content != content {
      throw StoreError.misplacedNote(note.id)
    }
    let url = notesFile(on: content)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var line = try Formats.line(entry)
    if try !endsWithNewline(url) { line.insert(UInt8(ascii: "\n"), at: 0) }
    let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: line)
    try handle.close()
  }

  private func endsWithNewline(_ url: URL) throws -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    guard size > 0 else { return true }
    try handle.seek(toOffset: size - 1)
    return try handle.read(upToCount: 1) == Data("\n".utf8)
  }
}
