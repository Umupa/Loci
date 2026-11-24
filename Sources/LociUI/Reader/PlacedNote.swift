import AppKit
import LociModel

/// A note with where its quote is in the reading text now, or `nil` when the words are gone and the note
/// is lost.
struct PlacedNote: Identifiable {
  let note: Note
  let range: NSRange?
  var original: NSRange?
  /// The pictures it covers, by their address in the item's text. A note saved before notes named their
  /// pictures finds them in the text where it is.
  var pictures: [String] = []

  init(note: Note, range: NSRange?, original: NSRange? = nil, pictures: [String]? = nil) {
    self.note = note
    self.range = range
    self.original = original
    self.pictures = pictures ?? note.pictures
  }

  var id: EntityID { note.id }

  /// The marked words, without the characters pictures stood on in notes saved before pictures were named.
  var words: String? {
    (note.excerpt ?? note.locator.quote?.text).flatMap(ReaderPassage.words)
  }

  /// The notes on places in the text, in the order of the text; lost notes after the rest, in the order they
  /// were saved. The thought on the whole item is not among them.
  static func place(_ notes: [Note], in text: ReadingText) -> [PlacedNote] {
    let placed = notes.filter { !$0.isWhole }.map { note in
      let original = note.locator.quote.flatMap { text.originalRange(of: $0) }
      let range = original.map { text.map.shown($0) }
      let pictures = note.pictures.isEmpty ? range.map { text.pictures(in: $0) } : nil
      return PlacedNote(note: note, range: range, original: original, pictures: pictures)
    }
    let found = placed.filter { $0.original != nil }.sorted {
      ($0.original?.location ?? 0) < ($1.original?.location ?? 0)
    }
    return found + placed.filter { $0.range == nil }
  }

  /// The highlight of each note that was found: underlined when it has a thought, with a dot after it when it
  /// has questions, and framed rather than washed where it is only pictures.
  static func marks(_ notes: [PlacedNote]) -> [ReaderMark] {
    notes.compactMap { placed in
      guard let range = placed.range else { return nil }
      return ReaderMark(
        note: placed.id, marginMark: !placed.note.exchanges.isEmpty, range: range, original: placed.original,
        thought: placed.note.thought, picture: !placed.pictures.isEmpty)
    }
  }
}
