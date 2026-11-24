import Foundation
import LociModel
import LociStore

extension AgentContext {
  /// The highlights listed in an introduction; the rest are in the notes file.
  static let introducedNotes = 30

  /// What a new session on an item is told before the person's first message there: what the item is,
  /// where its text and the person's highlights are, and the highlights so far.
  func introduction(to id: EntityID) -> String? {
    guard let item = try? store.item(id), let files = try? store.itemFiles(id) else { return nil }
    let notes = store.notes(on: .item(id)).value
    return Self.introduction(to: item, files: files, notes: notes, relativeTo: store.agentFolder)
  }

  static func introduction(to item: Item, files: ItemFiles, notes: [Note], relativeTo folder: URL) -> String {
    var about = ["\"\(item.title)\" (\(describe(item)))"]
    if !item.authors.isEmpty { about.append("by " + item.authors.joined(separator: ", ")) }
    if let site = item.site { about.append(site) }
    if let source = item.source { about.append(source.absoluteString) }
    let text =
      files.content.map { "Its text is in `\(path($0, from: folder))`. Read it before you answer." }
      ?? "Its text is not in the library yet; its folder is `\(path(files.folder, from: folder))`."
    var lines = [
      "This conversation is on an item in the library: the person reads it and asks you about it.",
      "",
      "The item: " + about.joined(separator: ", ") + ".",
    ]
    if let why = item.why { lines.append("Why they took it in, in their words: \(why)") }
    lines += [
      text,
      "Answer from the item, and say when you go beyond it.",
      "The person's highlights on it are in `\(path(files.notes, from: folder))`, one JSON object per line; "
        + "the one whose locator has no `#` is their thought on the whole item, and `pictures` names pictures "
        + "in the item's folder.",
    ]
    if let whole = notes.first(where: \.isWhole)?.thought {
      lines.append("Their thought on the whole item: " + whole)
    }
    let marked = notes.filter { !$0.isWhole && ($0.excerpt != nil || $0.thought != nil || !$0.pictures.isEmpty) }
    if !marked.isEmpty {
      lines.append("What they have marked so far:")
      for note in marked.prefix(introducedNotes) {
        let pictures = note.pictures.map { "[picture: \($0)]" }
        let words = ([note.excerpt?.replacing("\n", with: " ")].compactMap(\.self) + pictures).joined(separator: " ")
        let excerpt = "> " + (words.isEmpty ? "(a place)" : words)
        lines.append(excerpt + (note.thought.map { "\n  Their thought: " + $0 } ?? ""))
      }
      if marked.count > introducedNotes {
        lines.append("…and \(marked.count - introducedNotes) more in the notes file.")
      }
    }
    return lines.joined(separator: "\n") + "\n\n"
  }

  private static func describe(_ item: Item) -> String {
    switch item.kind {
    case .article: "an article"
    case .paper: "a paper, as a PDF"
    case .video: "a video; its transcript has a line per sentence with times in seconds"
    case .audio: "an audio episode; its transcript has a line per sentence with times in seconds"
    case .repository(let commit): "a code repository at commit \(commit)"
    case .book: "a book; only its title and authors are for you, its text is for the reader to read"
    }
  }

  /// `../library/…` from Loci's folder, the way Loci's own tools will reach it.
  static func path(_ url: URL, from folder: URL) -> String {
    let base = folder.resolvingSymlinksInPath().deletingLastPathComponent().path(percentEncoded: false)
    let full = url.standardizedFileURL.path(percentEncoded: false)
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return full.hasPrefix(prefix) ? "../" + full.dropFirst(prefix.count) : full
  }
}
