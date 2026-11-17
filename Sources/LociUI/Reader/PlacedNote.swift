import AppKit
import LociModel

/// A note with where its quote is in the reading text now, or `nil` when the words are gone and the note
/// is lost.
struct PlacedNote: Identifiable {
  let note: Note
  let range: NSRange?

  var id: EntityID { note.id }

  /// The notes in the order of the text; lost notes after the rest, in the order they were saved.
  static func place(_ notes: [Note], in text: ReadingText) -> [PlacedNote] {
    let plain = text.plain
    let placed = notes.map { note in
      PlacedNote(note: note, range: note.locator.quote?.range(in: plain).map { NSRange($0, in: plain) })
    }
    let found = placed.filter { $0.range != nil }.sorted { ($0.range?.location ?? 0) < ($1.range?.location ?? 0) }
    return found + placed.filter { $0.range == nil }
  }

  /// The highlight of each note that was found, with a dot after it when there is more than the highlight.
  static func marks(_ notes: [PlacedNote]) -> [ReaderMark] {
    notes.compactMap { placed in
      guard let range = placed.range else { return nil }
      let more = placed.note.thought != nil || !placed.note.exchanges.isEmpty
      return ReaderMark(kind: .note(placed.id, marginMark: more), range: range)
    }
  }
}
