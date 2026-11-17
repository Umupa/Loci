import Foundation

/// Cuts a byte stream into lines at LF only, the framing of JSON Lines.
///
/// Unicode line separators inside a line are left alone: they are legal inside JSON strings.
struct LineFramer {
  private var pending = Data()

  /// Takes the next chunk and returns the lines it completed, without their line endings.
  mutating func receive(_ chunk: Data) -> [Data] {
    pending.append(chunk)
    var lines: [Data] = []
    while let end = pending.firstIndex(of: 0x0A) {
      var line = pending[pending.startIndex..<end]
      if line.last == 0x0D { line = line.dropLast() }
      lines.append(Data(line))
      pending = Data(pending[pending.index(after: end)...])
    }
    return lines
  }
}
