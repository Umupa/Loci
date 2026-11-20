import Foundation
import Testing

@testable import LociModel

struct ItemTests {
  static let hash = "sha256:" + String(repeating: "0f", count: 32)

  @Test func eachKindSurvivesItemJSON() throws {
    let kinds: [Item.Kind] = [
      .article, .paper, .video(duration: .milliseconds(1_234_500)), .video(duration: nil),
      .audio(duration: .seconds(60)), .repository(commit: Fixture.commit),
    ]
    for kind in kinds {
      let item = try Item(
        id: Fixture.item, kind: kind, title: "Borg", authors: ["Verma"], source: URL(string: "https://example.com/a"),
        language: "zh-Hans", contentHash: ContentHash(Self.hash))

      #expect(try Fixture.roundTrip(item) == item)
    }
  }

  @Test func theReasonItWasTakenInSurvivesItemJSON() throws {
    let item = try Item(id: Fixture.item, kind: .article, title: "Borg", why: " To compare with work. ")

    #expect(item.why == "To compare with work.")
    #expect(try Fixture.roundTrip(item).why == "To compare with work.")
    #expect(try Item(id: Fixture.item, kind: .article, title: "Borg", why: "  ").why == nil)
  }

  @Test func readsAFlatItemFile() throws {
    let item = try Fixture.decode(
      Item.self, #"{"id":"\#(Fixture.item)","kind":"video","duration":1234.5,"title":"Talk"}"#)

    #expect(item.kind == .video(duration: .milliseconds(1_234_500)))
    #expect(item.authors.isEmpty)
    #expect(item.source == nil)
    #expect(item.why == nil)
  }

  static let broken = [
    #""kind":"article","duration":3,"title":"x""#,
    #""kind":"video","commit":"\#(Fixture.commit)","title":"x""#,
    #""kind":"repository","title":"x""#,
    #""kind":"repository","commit":"abc1234","title":"x""#,
    #""kind":"podcast","title":"x""#,
    #""kind":"article","title":" ""#,
    #""kind":"article","title":"x","source":"file:///tmp/a.md""#,
    #""kind":"article","title":"x","language":"english language""#,
    #""kind":"article","title":"x","contentHash":"md5:abc""#,
    #""kind":"audio","duration":0,"title":"x""#,
  ]

  @Test(arguments: broken)
  func fieldsThatDoNotFitTheKindAreRejected(fields: String) {
    #expect(throws: DecodingError.self) {
      try Fixture.decode(Item.self, #"{"id":"\#(Fixture.item)",\#(fields)}"#)
    }
  }

  @Test func durationIsKeptToTheMillisecond() throws {
    let item = try Item(id: Fixture.item, kind: .audio(duration: .seconds(1.0004)), title: "x")

    #expect(item.kind == .audio(duration: .milliseconds(1_000)))
  }

  @Test(arguments: [String(repeating: "a", count: 40), String(repeating: "b", count: 64)])
  func acceptsFullCommitHashes(text: String) {
    #expect(CommitID(text)?.description == text)
  }

  @Test(arguments: ["abc1234", String(repeating: "A", count: 40), String(repeating: "a", count: 41)])
  func rejectsShortOrMalformedCommitHashes(text: String) {
    #expect(CommitID(text) == nil)
  }
}
