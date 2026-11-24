import Foundation
import LociModel

/// The companion's index (`MEMORY.md`) and wiki (`memory/`). Only the daily review writes them: outside it
/// they are read-only on disk, and what the review left is kept beside the data folder, out of the
/// companion's reach, so a change made anywhere else is found and the next review is told of it.
extension Store {
  static let wikiFolder = "memory"
  /// Beside `agent/`, where no session works.
  static let keptMemoryFolder = "memory-kept"

  var wikiURL: URL { agentFolder.appending(path: Self.wikiFolder, directoryHint: .isDirectory) }
  private var keptURL: URL { root.appending(path: Self.keptMemoryFolder, directoryHint: .isDirectory) }

  /// The wiki's pages by name, in order.
  public func wikiPages() -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: wikiURL.path(percentEncoded: false))) ?? []
    return files.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.filter(WikiLink.isName).sorted()
  }

  /// A page's text; `nil` when there is no such page.
  public func wikiPage(_ name: String) throws -> String? {
    guard WikiLink.isName(name) else { return nil }
    return try optionalText(at: wikiURL.appending(path: "\(name).md"))
  }

  /// Writes a page for the app, the wiki locked again afterwards when it was.
  public func saveWikiPage(_ text: String, as name: String) throws {
    guard WikiLink.isName(name) else {
      throw StoreError.invalid(FileProblem(path: "memory/\(name).md", kind: .invalid, reason: "not a page name"))
    }
    try writingMemory { try write(Data(text.utf8), to: wikiURL.appending(path: "\(name).md")) }
  }

  /// Lets the index and the wiki be written, as during the daily review, or makes them read-only.
  public func setMemoryWritable(_ writable: Bool) throws {
    try FileManager.default.createDirectory(at: wikiURL, withIntermediateDirectories: true)
    let file = writable ? 0o644 : 0o444
    let folder = writable ? 0o755 : 0o555
    try FileManager.default.setAttributes(
      [.posixPermissions: folder], ofItemAtPath: wikiURL.path(percentEncoded: false))
    for url in memoryFiles() {
      try FileManager.default.setAttributes([.posixPermissions: file], ofItemAtPath: url.path(percentEncoded: false))
    }
  }

  /// Whether the index can be written now.
  public var memoryIsWritable: Bool {
    FileManager.default.isWritableFile(atPath: agentFolder.appending(path: Self.memoryFile).path(percentEncoded: false))
  }

  /// Runs `body` with the index and wiki writable, then puts them back as they were and keeps what is there now,
  /// so the app's own change is not taken for one made elsewhere.
  func writingMemory<Value>(_ body: () throws -> Value) throws -> Value {
    let was = memoryIsWritable
    try setMemoryWritable(true)
    defer { try? setMemoryWritable(was) }
    let value = try body()
    if !was, FileManager.default.fileExists(atPath: keptURL.path(percentEncoded: false)) { try keepMemory() }
    return value
  }

  /// Keeps the index and the wiki as they are now, to compare against later.
  public func keepMemory() throws {
    try? FileManager.default.removeItem(at: keptURL)
    try FileManager.default.createDirectory(
      at: keptURL.appending(path: Self.wikiFolder, directoryHint: .isDirectory), withIntermediateDirectories: true)
    for (path, data) in memoryContents() { try write(data, to: keptURL.appending(path: path)) }
  }

  /// The index and pages that differ from what was last kept, added and removed ones too, as paths under
  /// `agent/`; none when nothing was kept yet.
  public func memoryChangedSinceKept() -> [String] {
    guard FileManager.default.fileExists(atPath: keptURL.path(percentEncoded: false)) else { return [] }
    let now = memoryContents()
    var kept: [String: Data] = [:]
    let keptPages =
      (try? FileManager.default.contentsOfDirectory(
        atPath: keptURL.appending(path: Self.wikiFolder).path(percentEncoded: false))) ?? []
    for path in [Self.memoryFile] + keptPages.map({ "\(Self.wikiFolder)/\($0)" }) {
      if let data = try? Data(contentsOf: keptURL.appending(path: path)) { kept[path] = data }
    }
    return Set(now.keys).union(kept.keys).filter { now[$0] != kept[$0] }.sorted()
  }

  private func memoryFiles() -> [URL] {
    [agentFolder.appending(path: Self.memoryFile)]
      .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
      + wikiPages().map { wikiURL.appending(path: "\($0).md") }
  }

  /// The index and every page by path under `agent/`.
  private func memoryContents() -> [String: Data] {
    var contents: [String: Data] = [:]
    if let data = try? Data(contentsOf: agentFolder.appending(path: Self.memoryFile)) {
      contents[Self.memoryFile] = data
    }
    for page in wikiPages() {
      if let data = try? Data(contentsOf: wikiURL.appending(path: "\(page).md")) {
        contents["\(Self.wikiFolder)/\(page).md"] = data
      }
    }
    return contents
  }
}
