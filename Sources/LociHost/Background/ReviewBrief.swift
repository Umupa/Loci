import Foundation
import LociModel
import LociStore

/// What the app works out for the daily review before it starts, so the review does not have to find it: the
/// day's transcripts, links to pages that are not there, memory changed outside a review, whether it is the
/// week's review, and whether the index is split into a wiki for the first time.
struct ReviewBrief: Sendable, Equatable {
  /// The day's conversations and run records of the home, under its folder.
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

  /// What the person did with the home's cards up to the day's end, oldest first, for the review to write into
  /// WATCH.md.
  let feedback: [CardFeedback]

  struct CardFeedback: Sendable, Equatable {
    let card: EntityID
    let what: String
    let given: NextUp.Feedback
  }

  /// The feedback the review read, by card, to forget once it finished.
  var feedbackRead: [EntityID: [NextUp.Feedback]] {
    Dictionary(grouping: feedback, by: \.card).mapValues { $0.map(\.given) }
  }

  static let unsortedPage = "unsorted"

  /// A project's review is given only its own transcripts and memory, and never splits an older index.
  static func make(
    for day: Day, in home: Home, store: Store, timeZone: TimeZone, cards: [NextUp] = []
  ) -> ReviewBrief {
    let files = store.home(home)
    let pages = files.wikiPages()
    let index = files.index()
    let entries = MemoryEntry.lines(of: index) { _ in nil }.compactMap { line -> MemoryEntry? in
      if case .entry(let entry) = line { entry } else { nil }
    }
    var dead: [String] = []
    let texts = [("MEMORY.md", index)] + pages.map { ("memory/\($0).md", (try? files.wikiPage($0)) ?? "") }
    for (path, text) in texts {
      for link in WikiLink.all(in: text) where !pages.contains(link.name) {
        dead.append("\(path) → \(link.path)")
      }
    }
    let end = day.adding(days: 1).start(in: timeZone)
    let feedback = cards.filter { $0.home == home }.flatMap { card in
      (card.feedback ?? []).filter { $0.at < end }.map {
        CardFeedback(card: card.id, what: card.what, given: $0)
      }
    }.sorted { $0.given.at < $1.given.at }
    return ReviewBrief(
      transcripts: files.transcriptPaths().filter { $0.contains("/\(day)/") }.map(files.local).sorted(),
      deadLinks: Array(NSOrderedSet(array: dead)).compactMap { $0 as? String },
      changedElsewhere: files.memoryChangedSinceKept(),
      weekly: Weekday(of: day, in: timeZone) == .sunday,
      migrating: home == .chat && pages.isEmpty && !entries.isEmpty ? entries : nil,
      unsorted: pages.contains(unsortedPage), feedback: feedback)
  }

  /// After the first split: every entry of the old index whose words are now nowhere in the index or the wiki
  /// goes into `memory/unsorted.md`, so none is lost. Gives how many were kept that way.
  @discardableResult
  static func keepLost(_ entries: [MemoryEntry], store: Store) throws -> Int {
    let pages = store.home(.chat).wikiPages()
    let everything =
      ([(try? store.agentText(.memory)) ?? ""] + pages.map { (try? store.home(.chat).wikiPage($0)) ?? "" })
      .joined(separator: "\n")
    let lost = entries.filter { !$0.text.isEmpty && !everything.contains($0.text) }
    guard !lost.isEmpty else { return 0 }
    let current = (try? store.home(.chat).wikiPage(unsortedPage)) ?? "# Unsorted\n\n"
    let added = lost.map(\.line).joined(separator: "\n")
    try store.home(.chat).saveWikiPage(
      current.trimmingCharacters(in: .newlines) + "\n" + added + "\n", as: unsortedPage)
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
    if !feedback.isEmpty {
      lines.append(
        "- What the person did with today's cards. Write each declined one into WATCH.md as noise and each started "
          + "one as an example of what is worth telling:")
      lines += feedback.map {
        "  - \($0.given.kind == .declined ? "declined" : "started"): \($0.what)"
      }
    }
    return lines.joined(separator: "\n")
  }
}
