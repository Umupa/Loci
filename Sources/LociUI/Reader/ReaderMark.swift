import AppKit
import LociModel

/// A note's highlight, drawn over the text without changing it. A note with a thought or questions also
/// gets a mark in the margin.
struct ReaderMark: Equatable {
  let note: EntityID
  let marginMark: Bool
  /// In the reading text, in UTF-16 units.
  let range: NSRange
}
