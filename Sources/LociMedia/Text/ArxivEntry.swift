import Foundation

/// The first paper in an answer from arXiv's API, which is an Atom feed.
struct ArxivEntry: Hashable, Sendable {
  let title: String
  let authors: [String]
  let published: Date?

  /// `nil` when the feed has no paper in it; arXiv answers an unknown id with an empty feed or an entry
  /// titled `Error`.
  init?(atom: Data) {
    let reader = AtomReader()
    let parser = XMLParser(data: atom)
    parser.delegate = reader
    guard parser.parse(), let entry = reader.entry else { return nil }
    let title = entry.title.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    guard !title.isEmpty, title != "Error" else { return nil }
    self.title = title
    authors = entry.authors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    published = ArticleAssembler.date(entry.published)
  }
}

/// Collects the first `<entry>`'s title, author names and publication date.
private final class AtomReader: NSObject, XMLParserDelegate {
  struct Entry {
    var title = ""
    var authors: [String] = []
    var published = ""
  }

  private(set) var entry: Entry?
  private var current: Entry?
  private var path: [String] = []
  private var text = ""

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
    attributes: [String: String]
  ) {
    path.append(name)
    text = ""
    if name == "entry", entry == nil { current = Entry() }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    text += string
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    defer { path.removeLast() }
    guard current != nil else { return }
    switch (name, path.dropLast().last) {
    case ("title", "entry"): current?.title = text
    case ("published", "entry"): current?.published = text
    case ("name", "author"): current?.authors.append(text)
    case ("entry", _):
      entry = current
      current = nil
    default: break
    }
    text = ""
  }
}
