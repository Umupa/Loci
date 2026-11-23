import AppKit
import LociModel

/// A note with where its quote is in the reading text now, or `nil` when the words are gone and the note
/// is lost.
struct PlacedNote: Identifiable {
  let note: Note
  let range: NSRange?
  var original: NSRange?

  var id: EntityID { note.id }

  /// The notes in the order of the text; lost notes after the rest, in the order they were saved.
  static func place(_ notes: [Note], in text: ReadingText) -> [PlacedNote] {
    let placed = notes.map { note in
      let original = note.locator.quote.flatMap { text.originalRange(of: $0) }
      return PlacedNote(note: note, range: original.map { text.map.shown($0) }, original: original)
    }
    let found = placed.filter { $0.original != nil }.sorted {
      ($0.original?.location ?? 0) < ($1.original?.location ?? 0)
    }
    return found + placed.filter { $0.range == nil }
  }

  /// The highlight of each note that was found, with a dot after it when there is more than the highlight.
  static func marks(_ notes: [PlacedNote]) -> [ReaderMark] {
    notes.compactMap { placed in
      guard let range = placed.range else { return nil }
      let more = placed.note.thought != nil || !placed.note.exchanges.isEmpty
      return ReaderMark(note: placed.id, marginMark: more, range: range, original: placed.original)
    }
  }
}
