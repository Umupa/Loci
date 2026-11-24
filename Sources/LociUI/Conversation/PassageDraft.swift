import LociModel

/// A passage picked in the reader to ask Loci about, shown above the input field until it is sent.
struct PassageDraft: Equatable {
  let content: ContentRef
  let locator: Locator
  let excerpt: String
  /// By their address in the item's text.
  var pictures: [String] = []

  var passage: Passage { Passage(locator: locator, excerpt: excerpt, pictures: pictures) }
}
