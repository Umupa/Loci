import Foundation
import Testing

@testable import LociModel

struct LocatorTests {
  static let item = Fixture.item.description
  static let commit = Fixture.commit.description

  static let canonical = [
    "loci://library/\(item)#t=204.1,207.8",
    "loci://library/\(item)#t=0",
    "loci://library/\(item)#quote=调度器先过滤节点&pre=首先，&post=然后打分",
    "loci://library/\(item)#quote=a%20%26%20b%3D%23",
    "loci://library/\(item)#page=3",
    "loci://library/\(item)#page=3&rect=72,-10.5,200.25,14",
    "loci://library/\(item)#path=src/vm.rs&L=12-40&rev=\(commit)",
    "loci://library/\(item)#path=README.md&L=7&rev=\(commit)",
  ]

  @Test(arguments: canonical)
  func canonicalTextSurvivesParsingAndWritingBack(text: String) throws {
    let locator = try #require(Locator(text))

    #expect(locator.description == text)
    #expect(Locator(locator.description) == locator)
  }

  @Test func eachFormParsesToWhatItSays() throws {
    let expected: [(String, Locator)] = [
      (
        "loci://library/\(Self.item)#t=204.1,207.8",
        .item(Fixture.item, .time(try TimeSpan(start: .milliseconds(204_100), end: .milliseconds(207_800))))
      ),
      (
        "loci://library/\(Self.item)#quote=x&post=y",
        .item(Fixture.item, .quote(try TextQuote("x", after: "y")))
      ),
      (
        "loci://library/\(Self.item)#page=2&rect=1,2,3,4",
        .item(Fixture.item, .page(try PageRegion(page: 2, rect: .init(x: 1, y: 2, width: 3, height: 4))))
      ),
      (
        "loci://library/\(Self.item)#path=a/b.swift&L=3-5&rev=\(Self.commit)",
        .item(Fixture.item, .lines(try CodeLines(path: "a/b.swift", lines: 3...5, commit: Fixture.commit)))
      ),
    ]
    for (text, locator) in expected {
      #expect(Locator(text) == locator)
    }
  }

  @Test func quotesWithAwkwardCharactersSurviveAsValues() throws {
    let quote = try TextQuote(
      "50% of a&b = c#d (see [1])\n下一行", before: "  leading space", after: "emoji 🧭 and\u{3000}wide space")
    let locator = Locator.item(Fixture.item, .quote(quote))

    #expect(Locator(locator.description) == locator)
    #expect(!locator.description.contains(" "))
    #expect(locator.description.contains("下一行"))
  }

  @Test func readablyWrittenParametersInAnyOrderMeanTheSame() throws {
    let canonical = try #require(Locator("loci://library/\(Self.item)#path=a.rs&L=12&rev=\(Self.commit)"))

    #expect(Locator("loci://library/\(Self.item)#rev=\(Self.commit)&L=12-12&path=a.rs") == canonical)
    #expect(
      Locator("loci://library/\(Self.item)#post=b&quote=%E8%B0%83&pre=a")
        == Locator(
          "loci://library/\(Self.item)#quote=调&pre=a&post=b"))
    #expect(Locator("loci://library/\(Self.item)#t=1.50,2.000")?.description == "loci://library/\(Self.item)#t=1.5,2")
  }

  @Test func valuesSurviveWritingAndParsing() throws {
    let values: [Locator] = [
      .item(Fixture.item, .time(try TimeSpan(start: .seconds(0.0004)))),
      .item(Fixture.item, .time(try TimeSpan(start: .seconds(3_600), end: .milliseconds(3_600_001)))),
      .item(Fixture.item, .page(try PageRegion(page: 1, rect: .init(x: -0.004, y: 0.1, width: 0.01, height: 1e6)))),
    ]
    for locator in values {
      #expect(Locator(locator.description) == locator)
    }
  }

  static let invalid = [
    "",
    "https://library/\(item)#t=1",
    "loci://library/\(item)",
    "loci://library/\(item)#",
    "loci://library/not-an-id#t=1",
    "loci://library/3f2b8c1e-9d4a-4b6f-8a1c-2e5d7f9b0c3a#t=1",
    "loci://library/\(item.uppercased())#t=1",
    "loci://library/\(item)/extra#t=1",
    "loci://mentor/\(Fixture.id(2))/lesson/intro#quote=x",
    "loci://library/\(item)#t=1&t=2",
    "loci://library/\(item)#t=1&quote=x",
    "loci://library/\(item)#t=1&color=red",
    "loci://library/\(item)#t=5,5",
    "loci://library/\(item)#t=5,4",
    "loci://library/\(item)#t=-1",
    "loci://library/\(item)#t=1.0001",
    "loci://library/\(item)#t=1e3",
    "loci://library/\(item)#t=+1",
    "loci://library/\(item)#t=1,2,3",
    "loci://library/\(item)#quote=",
    "loci://library/\(item)#quote=%20%20",
    "loci://library/\(item)#quote=x&pre=",
    "loci://library/\(item)#pre=x",
    "loci://library/\(item)#quote=a b",
    "loci://library/\(item)#quote=a=b",
    "loci://library/\(item)#quote=a#b",
    "loci://library/\(item)#quote=%zz",
    "loci://library/\(item)#quote=%E8",
    "loci://library/\(item)#page=0",
    "loci://library/\(item)#page=two",
    "loci://library/\(item)#page=1&rect=1,2,3",
    "loci://library/\(item)#page=1&rect=1,2,0,4",
    "loci://library/\(item)#page=1&rect=1,2,-3,4",
    "loci://library/\(item)#page=1&rect=1.001,2,3,4",
    "loci://library/\(item)#rect=1,2,3,4",
    "loci://library/\(item)#path=a.rs&L=12",
    "loci://library/\(item)#path=a.rs&L=40-12&rev=\(commit)",
    "loci://library/\(item)#path=a.rs&L=0-3&rev=\(commit)",
    "loci://library/\(item)#path=../etc/passwd&L=1&rev=\(commit)",
    "loci://library/\(item)#path=/abs.rs&L=1&rev=\(commit)",
    "loci://library/\(item)#path=a//b.rs&L=1&rev=\(commit)",
    "loci://library/\(item)#path=a.rs&L=1&rev=abc1234",
    "loci://library/\(item)#path=&L=1&rev=\(commit)",
  ]

  @Test(arguments: invalid)
  func malformedTextIsRejectedRatherThanHalfParsed(text: String) {
    #expect(Locator(text) == nil)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Locator.self, from: JSONEncoder().encode(text))
    }
  }

  @Test func invalidPartsCannotBeBuiltDirectly() {
    #expect(throws: ModelError.self) { try TimeSpan(start: .seconds(-1)) }
    #expect(throws: ModelError.self) { try TimeSpan(start: .seconds(2), end: .seconds(2)) }
    #expect(throws: ModelError.self) { try TextQuote(" ") }
    #expect(throws: ModelError.self) { try TextQuote("x", before: "") }
    #expect(throws: ModelError.self) { try PageRegion(page: 0) }
    #expect(throws: ModelError.self) { try PageRegion.Rect(x: 0, y: 0, width: .infinity, height: 1) }
    #expect(throws: ModelError.self) { try PageRegion.Rect(x: 0, y: 0, width: 0.001, height: 1) }
    #expect(throws: ModelError.self) { try CodeLines(path: "a/../b", lines: 1...1, commit: Fixture.commit) }
    #expect(throws: ModelError.self) { try CodeLines(path: "a", lines: 0...1, commit: Fixture.commit) }
  }

  @Test func encodesAsItsTextInJSON() throws {
    let locator = try #require(Locator(Self.canonical[0]))

    #expect(String(decoding: try JSONEncoder().encode([locator]), as: UTF8.self).contains("t=204.1,207.8"))
    #expect(try Fixture.roundTrip(locator) == locator)
  }
}
