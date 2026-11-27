import Foundation
import LociMedia
import LociModel
import Testing

/// UP-S8 and UP-S9: `latest.json` keeps what earlier releases read and adds the zip, patches and notes.
struct ReleaseFeedTests {
  private static let dmg = "https://dl.umupa.fun/loci/Loci-Beta-1.9.0.dmg"
  private static let checksum = String(repeating: "a", count: 64)

  private static func latest(_ body: String) async throws -> AppRelease {
    let network = FakeNetwork([
      ReleaseFeed.loci.absoluteString: FakeNetwork.Answer(status: 200, type: "application/json", body: Data(body.utf8))
    ])
    return try await ReleaseFeed(network: network).latest()
  }

  @Test func theFeedFromEarlierReleasesStillReads() async throws {
    let release = try await Self.latest(
      #"{"version": "1.8.8", "sha256": "\#(Self.checksum)", "downloads": ["\#(Self.dmg)"]}"#)
    #expect(release.version == ReleaseVersion("1.8.8"))
    #expect(release.images == [URL(string: Self.dmg)!])
    #expect(release.archive == nil)
    #expect(release.patches.isEmpty)
    #expect(release.notes.isEmpty)
  }

  @Test func theFeedReadsTheArchivePatchesAndNotes() async throws {
    let zip = "https://dl.umupa.fun/loci/Loci-Beta-1.9.0.zip"
    let files = "https://dl.umupa.fun/loci/Loci-Beta-1.9.0.files.json"
    let patch = "https://dl.umupa.fun/loci/Loci-Beta-1.9.0.from-1.8.8.patch"
    let release = try await Self.latest(
      """
      {"version": "1.9.0", "sha256": "\(Self.checksum)", "downloads": ["\(Self.dmg)"],
       "archive": {"sha256": "\(String(repeating: "B", count: 64))", "size": 80, "downloads": ["\(zip)"]},
       "manifest": {"sha256": "\(String(repeating: "c", count: 64))", "size": 4, "downloads": ["\(files)"]},
       "patches": [{"from": "1.8.8", "sha256": "\(String(repeating: "d", count: 64))", "size": 13, "downloads": ["\(patch)"]},
                   {"from": "1.8.7", "sha256": "not a checksum", "size": 13, "downloads": ["\(patch)"]}],
       "notes": [{"version": "1.9.0", "changes": "- Patches.\\n- Notes that run\\n  on.\\n"}, {"version": "1.8.8", "changes": "- Waiting."}]}
      """)
    #expect(
      release.archive
        == ReleaseFile(checksum: String(repeating: "b", count: 64), size: 80, places: [URL(string: zip)!]))
    #expect(release.manifest?.places == [URL(string: files)!])
    #expect(release.patches.map(\.from) == [ReleaseVersion("1.8.8")!])
    #expect(release.patch(from: ReleaseVersion("1.8.8")!)?.patch.places == [URL(string: patch)!])
    #expect(release.patch(from: ReleaseVersion("1.8.7")!) == nil)
    #expect(release.notes.map(\.changes) == [["Patches.", "Notes that run on."], ["Waiting."]])
  }
}
