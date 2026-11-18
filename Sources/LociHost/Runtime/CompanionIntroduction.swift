import Foundation
import LociModel
import LociStore

extension MentorRun {
  /// What a mentor is told the first time a session of its own opens on an item: what the item is, where
  /// its text and the learner's notes are, and the notes so far. Said before the learner's first question.
  func introduction() -> String {
    guard let item = scope.item else { return "" }
    let store = context.store
    guard let described = try? store.item(item), let files = try? store.itemFiles(item) else { return "" }
    let notes = store.notes(on: .item(item)).value
    return Soul.companion(on: described, files: files, notes: notes) + "\n"
  }
}

extension Soul {
  /// Notes listed in the introduction; the rest are in the notes file.
  static let introducedNotes = 30

  static func companion(on item: Item, files: ItemFiles, notes: [Note]) -> String {
    var about = ["\"\(item.title)\" (\(kind(of: item)))"]
    if !item.authors.isEmpty { about.append("by " + item.authors.joined(separator: ", ")) }
    if let site = item.site { about.append(site) }
    if let source = item.source { about.append(source.absoluteString) }
    let text =
      files.content.map { "Its text is in `\($0.path(percentEncoded: false))`. Read it before you answer." }
      ?? "Its text is not in the library yet; the folder is `\(files.folder.path(percentEncoded: false))`."
    var lines = [
      "I am reading an item from my library and want you to read along and answer my questions about it.",
      "",
      "The item: " + about.joined(separator: ", ") + ".",
      text,
      "Answer from the item, and say when you go beyond it.",
      "My notes on it are in `\(files.notes.path(percentEncoded: false))`, one JSON object per line.",
    ]
    let marked = notes.filter { $0.excerpt != nil || $0.thought != nil }
    if !marked.isEmpty {
      lines.append("What I have marked so far:")
      for note in marked.prefix(introducedNotes) {
        let excerpt = note.excerpt.map { "> " + $0.replacing("\n", with: " ") } ?? "> (a place)"
        lines.append(excerpt + (note.thought.map { "\n  My thought: " + $0 } ?? ""))
      }
      if marked.count > introducedNotes {
        lines.append("…and \(marked.count - introducedNotes) more in the notes file.")
      }
    }
    lines.append("")
    lines.append("My question:")
    return lines.joined(separator: "\n")
  }

  private static func kind(of item: Item) -> String {
    switch item.kind {
    case .article: "an article"
    case .paper: "a paper, as a PDF"
    case .video: "a video; its transcript has a line per sentence with times in seconds"
    case .audio: "an audio episode; its transcript has a line per sentence with times in seconds"
    case .repository(let commit): "a code repository at commit \(commit)"
    }
  }
}
