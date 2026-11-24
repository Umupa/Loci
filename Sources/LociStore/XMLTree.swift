import Foundation

/// An XML element with its children, by local name; enough for the package files of an EPUB.
final class XMLTree {
  let name: String
  let attributes: [String: String]
  private(set) var children: [XMLTree] = []
  private var pieces: [Piece] = []

  private enum Piece {
    case text(String)
    case element(XMLTree)
  }

  init(name: String, attributes: [String: String]) {
    self.name = name
    self.attributes = attributes
  }

  /// `nil` when the data is not well-formed XML.
  static func parse(_ data: Data) -> XMLTree? {
    let builder = Builder()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.delegate = builder
    return parser.parse() ? builder.root : nil
  }

  /// An attribute by local name, whatever its prefix.
  func attribute(_ local: String) -> String? {
    attributes[local] ?? attributes.first { $0.key.hasSuffix(":" + local) }?.value
  }

  /// All the text inside, with runs of white space made one space.
  var text: String {
    let all = pieces.map { piece in
      switch piece {
      case .text(let text): text
      case .element(let element): element.text
      }
    }.joined()
    return all.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// Every element below this one with the local name, in document order.
  func all(_ local: String) -> [XMLTree] {
    children.flatMap { ($0.name == local ? [$0] : []) + $0.all(local) }
  }

  func first(_ local: String) -> XMLTree? {
    for child in children {
      if child.name == local { return child }
      if let found = child.first(local) { return found }
    }
    return nil
  }

  func children(_ local: String) -> [XMLTree] { children.filter { $0.name == local } }

  private final class Builder: NSObject, XMLParserDelegate {
    var root: XMLTree?
    private var open: [XMLTree] = []

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
      attributes: [String: String] = [:]
    ) {
      let element = XMLTree(name: name, attributes: attributes)
      if let parent = open.last {
        parent.children.append(element)
        parent.pieces.append(.element(element))
      } else {
        root = element
      }
      open.append(element)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      open.last?.pieces.append(.text(string))
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
      open.removeLast()
    }
  }
}
