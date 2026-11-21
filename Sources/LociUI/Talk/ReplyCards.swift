import Foundation
import LociModel

/// Something long Loci wrote out as a document instead of a run of bubbles: a fenced block marked
/// `loci-doc`, its first line `# title`, Markdown after.
struct LociDocument: Hashable {
  /// `nil` when the block does not begin with a heading.
  let title: String?
  let body: String

  /// The block's lines, without its fences.
  init(block: String) {
    let lines = block.split(separator: "\n", omittingEmptySubsequences: false).drop { $0.allSatisfy(\.isWhitespace) }
    if let first = lines.first, first.hasPrefix("# ") {
      title = first.dropFirst(2).trimmingCharacters(in: .whitespaces)
      body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
    } else {
      title = nil
      body = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
  }

  init(title: String?, body: String) {
    self.title = title
    self.body = body
  }

  /// The whole document as Markdown, its title a heading.
  var markdown: String {
    guard let title else { return body }
    return "# \(title)\n\n\(body)"
  }
}

/// A part of a bubble's words drawn on its own: words stay in the bubble, a document becomes a document
/// card, and links on lines of their own become link cards.
enum ReplyPiece: Equatable {
  case words(String)
  case document(LociDocument)
  case links([URL])

  /// The fence language that marks a document.
  static let documentMark = "loci-doc"

  /// The pieces of one bubble, in order. Links follow one another across blank lines; a link inside a
  /// sentence or a code block stays in the words. A document still being written is a document all the same.
  static func pieces(in bubble: String) -> [ReplyPiece] {
    var pieces: [ReplyPiece] = []
    var words: [Substring] = []
    var links: [URL] = []
    var blanks: [Substring] = []
    var document: (fence: Fence, lines: [Substring])?
    var fence: Fence?

    func flushWords() {
      let text = words.joined(separator: "\n").trimmingCharacters(in: .newlines)
      if !text.allSatisfy(\.isWhitespace) { pieces.append(.words(text)) }
      words = []
    }
    func flushLinks() {
      if !links.isEmpty { pieces.append(.links(links)) }
      links = []
      words.append(contentsOf: blanks)
      blanks = []
    }

    for line in bubble.split(separator: "\n", omittingEmptySubsequences: false) {
      if let open = document {
        if open.fence.closes(line) {
          pieces.append(.document(LociDocument(block: open.lines.joined(separator: "\n"))))
          document = nil
        } else {
          document?.lines.append(line)
        }
        continue
      }
      if let open = fence {
        if open.closes(line) { fence = nil }
        words.append(line)
        continue
      }
      if line.allSatisfy(\.isWhitespace) {
        if links.isEmpty { words.append(line) } else { blanks.append(line) }
        continue
      }
      if let url = link(on: line) {
        if links.isEmpty { flushWords() }
        blanks = []
        links.append(url)
        continue
      }
      flushLinks()
      if let opened = Fence(line) {
        if opened.language == documentMark {
          flushWords()
          document = (opened, [])
          continue
        }
        fence = opened
      }
      words.append(line)
    }
    if let open = document {
      flushLinks()
      flushWords()
      pieces.append(.document(LociDocument(block: open.lines.joined(separator: "\n"))))
    } else {
      blanks = []
      flushLinks()
      flushWords()
    }
    return pieces
  }

  /// The address a line holds and nothing else: bare, in angle brackets, or as the one Markdown link.
  static func link(on line: Substring) -> URL? {
    let text = line.trimmingCharacters(in: .whitespaces)
    let address: Substring
    if let match = text.wholeMatch(of: /\[[^\]]*\]\(<?(https?:\/\/[^\s)>]+)>?\)/) {
      address = match.output.1
    } else if let match = text.wholeMatch(of: /<?(https?:\/\/[^\s<>]+)>?/) {
      address = match.output.1
    } else {
      return nil
    }
    guard let url = URL(string: String(address)), url.host() != nil else { return nil }
    return url
  }

  /// A fenced block's opening line, with its language, which the same run of backticks or tildes closes.
  private struct Fence {
    let mark: Character
    let length: Int
    let language: String

    init?(_ line: Substring) {
      let rest = line.drop { $0 == " " }
      guard line.count - rest.count <= 3, let mark = rest.first, mark == "`" || mark == "~" else { return nil }
      let run = rest.prefix { $0 == mark }.count
      guard run >= 3 else { return nil }
      self.mark = mark
      length = run
      language = rest.dropFirst(run).trimmingCharacters(in: .whitespaces).lowercased()
    }

    func closes(_ line: Substring) -> Bool {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      return trimmed.count >= length && trimmed.allSatisfy { $0 == mark }
    }
  }
}

extension TalkRow {
  /// The rows of a reply's bubbles: words as bubbles, documents and links as cards between them. The
  /// last bubble of words carries the whole answer.
  static func rows(of bubbles: [String], in message: EntityID, answer: String?) -> [TalkRow] {
    let kinds: [Kind] = bubbles.flatMap(ReplyPiece.pieces).map { piece in
      switch piece {
      case .words(let words): .said(words, answer: nil)
      case .document(let document): .document(document)
      case .links(let links): .links(links)
      }
    }
    let last = kinds.lastIndex { if case .said = $0 { true } else { false } }
    return kinds.enumerated().map { part, kind in
      var kind = kind
      if part == last, case .said(let words, _) = kind { kind = .said(words, answer: answer) }
      return TalkRow(id: ID(message: message, part: part), kind: kind, reply: message)
    }
  }

  /// Links in a reply that only blank lines kept apart share one stack, under the first one's id.
  static func joiningLinks(_ rows: [TalkRow]) -> [TalkRow] {
    var joined: [TalkRow] = []
    for row in rows {
      if case .links(let more) = row.kind, let last = joined.last, last.reply == row.reply,
        case .links(let links) = last.kind
      {
        joined[joined.count - 1] = TalkRow(id: last.id, kind: .links(links + more), reply: last.reply)
      } else {
        joined.append(row)
      }
    }
    return joined
  }
}
