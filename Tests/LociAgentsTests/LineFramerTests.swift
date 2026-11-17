import Foundation
import Testing

@testable import LociAgents

struct LineFramerTests {
  private func lines(_ chunks: [Data]) -> [String] {
    var framer = LineFramer()
    return chunks.flatMap { framer.receive($0) }.map { String(decoding: $0, as: UTF8.self) }
  }

  @Test func aLineSplitAcrossChunksArrivesWhole() {
    #expect(lines([Data("{\"a\":".utf8), Data("1}\n{\"b\"".utf8), Data(":2}\n".utf8)]) == ["{\"a\":1}", "{\"b\":2}"])
  }

  @Test func aLineWithoutItsEndingIsHeldBack() {
    #expect(lines([Data("{\"a\":1}".utf8)]) == [])
  }

  @Test func aCharacterSplitAcrossChunksSurvives() {
    let bytes = Array("\"课\"\n".utf8)
    #expect(lines([Data(bytes[..<2]), Data(bytes[2...])]) == ["\"课\""])
  }

  @Test func unicodeLineSeparatorsDoNotEndALine() {
    #expect(lines([Data("\"a\u{2028}b\u{2029}c\"\n".utf8)]) == ["\"a\u{2028}b\u{2029}c\""])
  }

  @Test func aCarriageReturnBeforeTheLineFeedIsDropped() {
    #expect(lines([Data("one\r\ntwo\n".utf8)]) == ["one", "two"])
  }
}
