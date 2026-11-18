import LociModel
import Testing

/// R-S7: while the Mac behind the window cannot take changes, every control that would change its data is off.
struct ChangesDataTests {
  /// What the reader changes just by reading: where they are, what they have read. These are sent quietly and
  /// wait for the Mac to come back; no control sends them.
  static let byReading: Set = ["MarkRead", "SaveReadingPosition", "SeeLesson"]

  /// A file that sends a command `Wire` marks as a write has to say how its control goes quiet: marked
  /// `.changesData()`, reading `changesAllowed`, or with an `OfflineLine` standing in its place.
  @Test func everyFileThatChangesDataGoesQuietOffline() throws {
    let writes = Wire.commands.filter { $0.effect == .writes }.map { String(describing: $0.command) }
    for (path, text) in try CopyTests.sources() {
      let sent = try writes.filter { name in
        try !Self.byReading.contains(name) && text.contains(Regex("\\b\(name)\\("))
      }
      guard !sent.isEmpty else { continue }
      let quiet = ["changesData(", "changesAllowed", "offlineLineInstead("].contains { text.contains($0) }
      #expect(
        quiet,
        "\(path) sends \(sent.sorted()); mark the control that sends them with .changesData() so it is off offline")
    }
  }
}
