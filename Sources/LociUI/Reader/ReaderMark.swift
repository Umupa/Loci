import AppKit
import LociModel

/// Something the reader draws over the text without changing it: a glossary term to hover, or a
/// paragraph the mentor changed since the reader last saw the lesson.
struct ReaderMark: Equatable {
  enum Kind: Equatable {
    case term(Glossary.Term)
    case revised
  }

  let kind: Kind
  /// In the reading text, in UTF-16 units.
  let range: NSRange

  /// The first use of each glossary term in the text, except terms this lesson itself teaches.
  static func terms(of glossary: Glossary, in text: ReadingText, lesson: Lesson.Slug?) -> [ReaderMark] {
    let plain = text.plain
    return glossary.firstUses(in: plain, in: lesson).map {
      ReaderMark(kind: .term($0.term), range: NSRange($0.range, in: plain))
    }
  }

  /// The paragraphs of `text` that are new or changed since `previous`.
  static func revisions(from previous: ReadingText, to text: ReadingText) -> [ReaderMark] {
    let old = previous.plain.components(separatedBy: "\n")
    let new = text.plain.components(separatedBy: "\n")
    var starts: [Int] = []
    var offset = 0
    for paragraph in new {
      starts.append(offset)
      offset += (paragraph as NSString).length + 1
    }
    return new.difference(from: old).insertions.compactMap { change in
      guard case .insert(let index, let paragraph, _) = change, !paragraph.trimmingCharacters(in: .whitespaces).isEmpty
      else { return nil }
      return ReaderMark(kind: .revised, range: NSRange(location: starts[index], length: (paragraph as NSString).length))
    }
  }
}
