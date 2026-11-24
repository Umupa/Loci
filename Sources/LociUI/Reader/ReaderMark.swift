import AppKit
import LociModel

/// A note's highlight, drawn over the text without changing it. A highlight with a thought is underlined in
/// amber, one with questions also gets a dot after it, and a picture in it is framed rather than washed.
struct ReaderMark: Equatable {
  let note: EntityID
  let marginMark: Bool
  /// In the reading text, in UTF-16 units.
  let range: NSRange
  var original: NSRange?
  var thought: String?
  var picture = false
}
