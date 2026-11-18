/// Puts Whisper's tokens back into words. A token that starts with a space starts a word; so does every
/// Chinese, Japanese or Korean character, since those scripts have no spaces. Anything else, a piece of a
/// longer word or a punctuation mark, joins the word before it. A character split across two tokens is
/// held until its last byte arrives.
struct WordJoiner {
  private var words: [SpokenWord] = []
  private var pending: (bytes: [UInt8], start: Duration, end: Duration)?

  mutating func add(_ bytes: [UInt8], start: Duration, end: Duration) {
    guard !bytes.isEmpty else { return }
    if let current = pending, String(validating: current.bytes, as: UTF8.self) == nil {
      pending = (current.bytes + bytes, current.start, end)
      return
    }
    let startsWord = bytes.first == UInt8(ascii: " ") || Self.isDense(bytes) || Self.isDense(pending?.bytes ?? [])
    if startsWord || pending == nil {
      flush()
      pending = (bytes, start, end)
    } else if let current = pending {
      pending = (current.bytes + bytes, current.start, end)
    }
  }

  mutating func finish() -> [SpokenWord] {
    flush()
    defer { words = [] }
    return words
  }

  private mutating func flush() {
    guard let current = pending, let text = String(validating: current.bytes, as: UTF8.self) else { return }
    pending = nil
    words.append(SpokenWord(text: text, start: current.start, end: current.end))
  }

  /// Whether the text is in a script written without spaces; for a character still missing its last bytes,
  /// its first byte tells.
  private static func isDense(_ bytes: [UInt8]) -> Bool {
    if let lead = bytes.first, String(validating: bytes, as: UTF8.self) == nil {
      return (0xE3...0xED).contains(lead)
    }
    guard let text = String(validating: bytes, as: UTF8.self),
      let scalar = text.unicodeScalars.last(where: { !$0.properties.isWhitespace })
    else { return false }
    return (0x3040...0x30FF).contains(scalar.value) || (0x3400...0x9FFF).contains(scalar.value)
      || (0xAC00...0xD7AF).contains(scalar.value)
  }
}
