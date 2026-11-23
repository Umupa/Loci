import Foundation
import LociModel
import Testing

@testable import LociTool

struct FeelingToolTests {
  private func score(_ value: Int) throws -> Score { try #require(Score(value)) }

  @Test func moodSleepAndWakeAreReadWithTheirWords() throws {
    #expect(
      try Request.parse(["mood", "here", "annoyed", "3", "they", "ignored", "me"]).request
        == .feeling(.here(word: "annoyed", valence: try score(3), why: "they ignored me")))
    #expect(
      try Request.parse(["mood", "base", "tired", "5", "2", "long day"]).request
        == .feeling(.base(word: "tired", valence: try score(5), energy: try score(2), why: "long day")))
    #expect(try Request.parse(["sleep"]).request == .feeling(.sleep))
    #expect(try Request.parse(["wake"]).request == .feeling(.wake))
  }

  @Test func aScoreOutsideZeroToTenOrAMissingReasonSaysHowToWriteIt() {
    for words in [
      ["mood", "here", "happy", "11", "why"], ["mood", "here", "happy", "7"], ["mood", "base", "ok", "5", "x", "why"],
      ["mood", "happy", "7", "why"], ["sleep", "now"],
    ] {
      #expect(throws: UsageError.self) { try Request.parse(words) }
    }
  }

  @Test func theReplyIsHowTheCompanionFeelsAfterwards() async throws {
    let reply = "Feeling: sleepy, valence 5/10, energy 3/10"
    let data = try JSONEncoder().encode(reply)
    let line = ScriptedLine { _ in [.success(data)] }
    let outcome = await Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }.run(
      .feeling(.sleep), json: false)

    #expect(outcome == .worked(reply))
    #expect(line.requests == [.feeling(.sleep)])
  }
}
