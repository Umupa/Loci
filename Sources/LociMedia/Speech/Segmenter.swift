import Foundation
import LociModel
import NaturalLanguage

/// Cuts recognized words into sentences of one or two subtitle lines. NaturalLanguage finds where sentences
/// and words end; a sentence too long for two lines is cut where the speaker paused or a clause begins,
/// never inside a word.
public struct Segmenter: Sendable {
  /// Characters on one line for scripts with spaces between words, and for Chinese, Japanese and Korean.
  let lineLength: (spaced: Int, dense: Int)

  public init(lineLength: (spaced: Int, dense: Int) = (42, 18)) {
    self.lineLength = lineLength
  }

  /// Splits off every sentence that is surely finished. The last one may still be growing while speech is
  /// being recognized, so its words come back to be passed in again with the next ones.
  public func finished(_ words: [SpokenWord]) -> (segments: [Transcript.Segment], rest: [SpokenWord]) {
    let sentences = self.sentences(words)
    guard let last = sentences.last else { return ([], []) }
    return (sentences.dropLast().flatMap(lines), last)
  }

  /// Every sentence, the last one included, cut into lines.
  public func segments(_ words: [SpokenWord]) -> [Transcript.Segment] {
    sentences(words).flatMap(lines)
  }

  func sentences(_ words: [SpokenWord]) -> [[SpokenWord]] {
    let words = words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard !words.isEmpty else { return [] }
    let text = words.map(\.text).joined()
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    let ends = Set(tokenizer.tokens(for: text.startIndex..<text.endIndex).map(\.upperBound))
    var sentences: [[SpokenWord]] = [[]]
    var position = text.startIndex
    for word in words {
      sentences[sentences.count - 1].append(word)
      position = text.index(position, offsetBy: word.text.count)
      let after = text[position...].prefix { $0.isWhitespace }
      if ends.contains(position) || ends.contains(after.endIndex), position < text.endIndex { sentences.append([]) }
    }
    return sentences.filter { !$0.isEmpty }
  }

  /// A sentence longer than two lines is cut at its best place, again and again.
  func lines(_ sentence: [SpokenWord]) -> [Transcript.Segment] {
    let text = Self.joined(sentence)
    let limit = 2 * (Self.isDense(text) ? lineLength.dense : lineLength.spaced)
    guard text.count > limit, sentence.count > 1, let cut = bestCut(sentence, limit: limit) else {
      return Self.segment(sentence).map { [$0] } ?? []
    }
    return lines(Array(sentence[..<cut])) + lines(Array(sentence[cut...]))
  }

  /// The index of the word that starts the second half: after a long pause or a clause mark, before a word
  /// that opens a clause, near the middle; never inside a word as NaturalLanguage sees it.
  private func bestCut(_ sentence: [SpokenWord], limit: Int) -> Int? {
    let text = sentence.map(\.text).joined()
    let wordEnds = Self.wordBoundaries(text)
    let total = Double(Self.joined(sentence).count)
    var best: (index: Int, score: Double)?
    var offset = 0
    for index in 1..<sentence.count {
      offset += sentence[index - 1].text.count
      let boundary = text.index(text.startIndex, offsetBy: offset)
      let next = sentence[index].text
      guard next.first?.isWhitespace == true || wordEnds.contains(boundary) else { continue }
      let left = Double(Self.joined(Array(sentence[..<index])).count)
      let pause = Double((sentence[index].start - sentence[index - 1].end).roundedMillisecondsValue) / 1000
      var score = min(max(pause, 0), 1.5) * 3
      if let mark = sentence[index - 1].text.trimmingCharacters(in: .whitespaces).last, Self.clauseMarks.contains(mark)
      {
        score += 2
      }
      if Self.opensClause(next) { score += 1 }
      score -= abs(left - (total - left)) / total * 3
      if left < Double(limit) / 6 || total - left < Double(limit) / 6 { score -= 3 }
      if score > (best?.score ?? -.infinity) { best = (index, score) }
    }
    return best?.index
  }

  static let clauseMarks: Set<Character> = [",", ";", ":", "，", "；", "：", "、", "—", "–"]
  static let clauseOpeners: Set<String> = [
    "and", "but", "or", "so", "because", "which", "that", "who", "when", "while", "if", "although", "though",
    "where", "since", "unless", "until", "然后", "但是", "可是", "因为", "所以", "而且", "如果", "虽然", "不过", "就是",
  ]

  private static func opensClause(_ word: String) -> Bool {
    let plain = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
    if clauseOpeners.contains(plain) { return true }
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = plain
    guard !plain.isEmpty else { return false }
    let (tag, _) = tagger.tag(at: plain.startIndex, unit: .word, scheme: .lexicalClass)
    return tag == .conjunction
  }

  private static func wordBoundaries(_ text: String) -> Set<String.Index> {
    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var boundaries: Set<String.Index> = []
    for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
      boundaries.insert(range.lowerBound)
      boundaries.insert(range.upperBound)
    }
    return boundaries
  }

  static func joined(_ words: [SpokenWord]) -> String {
    words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func isDense(_ text: String) -> Bool {
    let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
    let dense = letters.filter {
      (0x3040...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value)
        || (0xAC00...0xD7AF).contains($0.value)
    }
    return !letters.isEmpty && dense.count * 2 > letters.count
  }

  static func segment(_ words: [SpokenWord]) -> Transcript.Segment? {
    guard let first = words.first, let last = words.last else { return nil }
    let end = max(last.end, words.map(\.end).max() ?? last.end, first.start + .milliseconds(1))
    return try? Transcript.Segment(start: first.start, end: end, text: joined(words))
  }
}

extension Duration {
  var roundedMillisecondsValue: Int {
    let (seconds, attoseconds) = components
    return Int(seconds) * 1000 + Int((Double(attoseconds) / 1e15).rounded())
  }
}
