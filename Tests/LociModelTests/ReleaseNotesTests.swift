import Foundation
import LociModel
import Testing

/// UP-S9: the update shows what changed in every version between the one running and the new one.
struct ReleaseNotesTests {
  @Test func changesSinceListTheVersionsAfterTheRunningOneNewestFirst() {
    let notes = ["1.8.7", "1.9.0", "1.8.8", "1.8.6", "1.9.1"].map {
      ReleaseNotes(version: ReleaseVersion($0)!, changes: ["in \($0)"])
    }
    let release = AppRelease(
      version: ReleaseVersion("1.9.0")!, image: URL(string: "https://example.com/a.dmg")!,
      checksum: String(repeating: "0", count: 64), notes: notes)
    #expect(release.changes(since: ReleaseVersion("1.8.7")!).map(\.version.description) == ["1.9.0", "1.8.8"])
  }

  @Test func aSectionSplitsIntoChangesThatMayRunOverSeveralLines() {
    let notes = ReleaseNotes(version: ReleaseVersion("1.9.0")!, section: "- One `code`.\n- Two\n  more.\n\n- Three")
    #expect(notes.changes == ["One `code`.", "Two more.", "Three"])
  }

  @Test func aReleaseStagedBeforeThereWereNotesStillReads() throws {
    let old =
      #"{"version": {"major": 1, "minor": 2, "patch": 0}, "images": ["https://example.com/a.dmg"], "checksum": "00"}"#
    let release = try JSONDecoder().decode(AppRelease.self, from: Data(old.utf8))
    #expect(release.notes.isEmpty)
    #expect(release.archive == nil)
  }
}
