import Foundation
import GRDB
import LociModel

/// The transcripts: `conversations/` and `runs/` under `agent/`, every word said and every run in the
/// background, as the app wrote them. They are searched with `loci recall`, never shown whole to the companion.
extension Store {
  /// Every transcript, as a path relative to `agent/`, in no order.
  public func transcriptPaths() -> [String] {
    [Self.conversationsFolder, Self.runsFolder].flatMap { folder -> [String] in
      let base = agentFolder.appending(path: folder, directoryHint: .isDirectory)
      let days = (try? FileManager.default.contentsOfDirectory(atPath: base.path(percentEncoded: false))) ?? []
      return days.filter { Day($0) != nil }.flatMap { day in
        let files =
          (try? FileManager.default.contentsOfDirectory(
            atPath: base.appending(path: day).path(percentEncoded: false))) ?? []
        return files.filter { $0.hasSuffix(".md") }.map { "\(folder)/\(day)/\($0)" }
      }
    }
  }

  /// The text of a transcript; `nil` when it is gone. Only paths under `conversations/` and `runs/` are read.
  public func transcript(at path: String) throws -> String? {
    let parts = path.split(separator: "/").map(String.init)
    guard parts.count == 3, [Self.conversationsFolder, Self.runsFolder].contains(parts[0]), Day(parts[1]) != nil
    else { throw StoreError.invalid(FileProblem(path: path, kind: .invalid, reason: "not a transcript")) }
    return try optionalText(
      at: agentFolder.appending(path: parts[0]).appending(path: parts[1]).appending(path: try Self.plainName(parts[2])))
  }
}

/// How a transcript is cut for searching: by blank lines, headings left out, so a hit is a message or a section.
enum Transcripts {
  static func passages(of text: String) -> [String] {
    text.components(separatedBy: "\n\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && !$0.hasPrefix("# ") }
  }
}

extension StoreDatabase {
  /// Reads the transcript at `path` again and replaces what the search knows of it.
  public func indexTranscript(_ path: String, from store: Store) throws {
    let update = MirrorUpdate.transcript(
      path, passages: Transcripts.passages(of: (try store.transcript(at: path)) ?? ""))
    try queue.write { db in try update.write(db) }
  }

  /// Passages of conversations and run records that hold every word, best first.
  public func recall(_ text: String, limit: Int = 20) throws -> [RecallHit] {
    guard let query = SearchText.query(text) else { return [] }
    let terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
    let rows = try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT transcript.original AS original, transcript_file.path AS path FROM transcript
          JOIN transcript_file ON transcript_file.transcript_rowid = transcript.rowid
          WHERE transcript MATCH ? ORDER BY bm25(transcript) LIMIT ?
          """,
        arguments: [query, limit])
    }
    return rows.map { row in
      let path: String = row["path"]
      let original: String = row["original"]
      let day = path.split(separator: "/").dropFirst().first.flatMap { Day(String($0)) }
      return RecallHit(path: path, day: day, snippet: Self.snippet(of: terms, in: original))
    }
  }
}
