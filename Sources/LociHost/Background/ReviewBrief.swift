import Foundation
import LociModel
import LociStore

/// What the app works out for the daily review before it starts, so the review does not have to find it: the
/// day's transcripts, links to pages that are not there, memory changed outside a review, whether it is the
/// week's review, and whether the index is split into a wiki for the first time.
struct ReviewBrief: Sendable, Equatable {
  /// The day's conversations and run records, under `agent/`.
  let transcripts: [String]
  /// `MEMORY.md → memory/x.md`, for each link to a page that does not exist.
  let deadLinks: [String]
  /// The index and pages that changed since the last review ended.
  let changedElsewhere: [String]
  /// Sunday's review goes over the whole wiki.
  let weekly: Bool
  /// The index's entries before it is first split into a wiki, each to be kept; `nil` once there is a wiki.
  let migrating: [MemoryEntry]?
  /// `memory/unsorted.md` holds entries the app kept for the review to put in place.
  let unsorted: Bool

  static let unsortedPage = "unsorted"

  static func make(for day: Day, store: Store, timeZone: TimeZone) -> ReviewBrief {
    let pages = store.wikiPages()
    let index = (try? store.agentText(.memory)) ?? ""
    let entries = MemoryEntry.lines(of: index) { _ in nil }.compactMap { line -> MemoryEntry? in
      if case .entry(let entry) = line { entry } else { nil }
    }
    var dead: [String] = []
    let files = [("MEMORY.md", index)] + pages.map { ("memory/\($0).md", (try? store.wikiPage($0)) ?? "") }
    for (path, text) in files {
      for link in WikiLink.all(in: text) where !pages.contains(link.name) {
        dead.append("\(path) → \(link.path)")
      }
    }
    return ReviewBrief(
      transcripts: store.transcriptPaths().filter { $0.contains("/\(day)/") }.sorted(),
      deadLinks: Array(NSOrderedSet(array: dead)).compactMap { $0 as? String },
      changedElsewhere: store.memoryChangedSinceKept(),
      weekly: Weekday(of: day, in: timeZone) == .sunday,
      migrating: pages.isEmpty && !entries.isEmpty ? entries : nil,
      unsorted: pages.contains(unsortedPage))
  }

  /// After the first split: every entry of the old index whose words are now nowhere in the index or the wiki
  /// goes into `memory/unsorted.md`, so none is lost. Gives how many were kept that way.
  @discardableResult
  static func keepLost(_ entries: [MemoryEntry], store: Store) throws -> Int {
    let pages = store.wikiPages()
    let everything = ([(try? store.agentText(.memory)) ?? ""] + pages.map { (try? store.wikiPage($0)) ?? "" })
      .joined(separator: "\n")
    let lost = entries.filter { !$0.text.isEmpty && !everything.contains($0.text) }
    guard !lost.isEmpty else { return 0 }
    let current = (try? store.wikiPage(unsortedPage)) ?? "# Unsorted\n\n"
    let added = lost.map(\.line).joined(separator: "\n")
    try store.saveWikiPage(current.trimmingCharacters(in: .newlines) + "\n" + added + "\n", as: unsortedPage)
    return lost.count
  }

  /// What the review is told of all this, as lines for its prompt.
  var checks: String {
    var lines: [String] = []
    if let migrating {
      lines.append(
        "- First, split MEMORY.md: it is still the whole of your memory. Make it an index and move the detail "
          + "into pages in memory/. Keep each of its \(migrating.count) entries, word for word, in the index or on "
          + "a page.")
    }
    if unsorted {
      lines.append(
        "- memory/unsorted.md holds entries the app kept for you. Put each where it belongs, then delete the page.")
    }
    if !changedElsewhere.isEmpty {
      lines.append(
        "- These changed outside a review: " + changedElsewhere.joined(separator: ", ")
          + ". Check each change against the transcripts: keep what is right, undo what is not.")
    }
    if !deadLinks.isEmpty {
      lines.append(
        "- These links point to pages that do not exist: " + deadLinks.joined(separator: "; ") + ". Fix them.")
    }
    if weekly {
      lines.append(
        "- It is Sunday: go over the whole wiki. Merge what repeats, split what grew too long, drop what no longer holds."
      )
    }
    return lines.joined(separator: "\n")
  }
}
