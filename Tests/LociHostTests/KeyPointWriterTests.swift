import Foundation
import LociModel
import Testing

@testable import LociHost

/// K-S3, K-S4: an agent picks as many key points as asked, with reasons for this reader.
struct KeyPointWriterTests {
  typealias Replies = TranscriptAgentTests.Replies

  static let reader = KeyPointReader(
    language: "zh-Hans", profile: "Learns distributed systems for an infra job.", why: "For the interview next week")

  static func writer(_ agent: FakeAgent, outlinePiece: Int = 200, passagePiece: Int = 150) -> AgentTranscriptAgent {
    AgentTranscriptAgent(
      runtime: Runtime(provider: .codex), agents: { $0 == .codex ? agent : nil }, outlinePiece: outlinePiece,
      passagePiece: passagePiece)
  }

  static func stretches(_ starts: [Int], length: Int = 4) -> String {
    let points = starts.map { #"{"start": \#($0), "end": \#($0 + length), "title": "T\#($0)", "reason": "R"}"# }
    return #"{"keyPoints": [\#(points.joined(separator: ", "))]}"#
  }

  static func transcript(_ count: Int) throws -> KeyPointSource {
    .transcript(try TranscriptAgentTests.transcript(count), title: "Talk")
  }

  @Test func aShortTranscriptIsPickedInOneTurnToTheChosenCount() async throws {
    let agent = FakeAgent { _ in .reply(Self.stretches([0, 10, 20, 30])) }

    let points = try await Self.writer(agent).keyPoints(of: try Self.transcript(30), count: .some, for: Self.reader)

    #expect(points.count == 4)
    #expect(points.first?.span == (try TimeSpan(start: .zero, end: .seconds(4))))
    #expect(agent.prompts.count == 1)
    #expect(agent.prompts.first?.contains("Pick 4 to 6") == true)
  }

  @Test func aLongTranscriptIsPickedFromCandidatesToTheChosenCount() async throws {
    let agent = FakeAgent { prompt in
      if prompt.contains("part 1 of 3") { return .reply(Self.stretches([0, 10, 20])) }
      if prompt.contains("part 2 of 3") { return .reply(Self.stretches([40, 50])) }
      if prompt.contains("part 3 of 3") { return .reply(Self.stretches([80, 90, 100, 110])) }
      return .reply(Self.stretches([10, 50, 90]))
    }

    let points = try await Self.writer(agent, outlinePiece: 20).keyPoints(
      of: try Self.transcript(60), count: .few, for: Self.reader)

    #expect(points.compactMap(\.span?.start) == [.seconds(10), .seconds(50), .seconds(90)])
    #expect(agent.prompts.count == 4)
    #expect(agent.prompts.last?.contains("[40.0-44.0] T40: R") == true)
    #expect(agent.prompts.last?.contains("Pick 3 to 4") == true)
  }

  @Test func aFinalPickThatIsNotACandidateIsAskedAgain() async throws {
    let replies = Replies([Self.stretches([10, 50, 70]), Self.stretches([10, 50, 90])])
    let agent = FakeAgent { prompt in
      if prompt.contains("part 1 of 2") { return .reply(Self.stretches([0, 10, 20])) }
      if prompt.contains("part 2 of 2") { return .reply(Self.stretches([50, 90])) }
      return .reply(replies.next())
    }

    let points = try await Self.writer(agent, outlinePiece: 25).keyPoints(
      of: try Self.transcript(50), count: .few, for: Self.reader)

    #expect(points.count == 3)
    #expect(agent.prompts.count == 4)
  }

  @Test func anAnswerWithTooManyKeyPointsIsAskedAgainThenFails() async throws {
    let agent = FakeAgent { _ in .reply(Self.stretches([0, 10, 20, 30, 40])) }

    await #expect(
      throws: HostError.invalidRequest("The agent's answer could not be used: 5 key points came back for 3…4")
    ) {
      try await Self.writer(agent).keyPoints(of: try Self.transcript(30), count: .few, for: Self.reader)
    }
    #expect(agent.prompts.count == 2)
  }

  @Test func overlappingKeyPointsAreAskedForAgain() async throws {
    let replies = Replies([Self.stretches([0, 2, 20], length: 6), Self.stretches([0, 10, 20])])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    let points = try await Self.writer(agent).keyPoints(of: try Self.transcript(30), count: .few, for: Self.reader)

    #expect(points.count == 3)
    #expect(agent.prompts.count == 2)
  }

  @Test func aShortSourceAsksForNoMoreThanItHas() async throws {
    let agent = FakeAgent { _ in .reply(Self.stretches([0, 2], length: 2)) }

    let points = try await Self.writer(agent).keyPoints(of: try Self.transcript(2), count: .some, for: Self.reader)

    #expect(points.count == 2)
    #expect(agent.prompts.first?.contains("Pick exactly 2") == true)
  }

  @Test func thePromptCarriesTheReadersLanguageWhyTheyLearnAndWhyTheyKeptIt() async throws {
    let agent = FakeAgent { _ in .reply(Self.stretches([0, 10, 20])) }

    _ = try await Self.writer(agent).keyPoints(of: try Self.transcript(30), count: .few, for: Self.reader)

    let prompt = try #require(agent.prompts.first)
    #expect(prompt.contains("`zh-Hans`"))
    #expect(prompt.contains("Learns distributed systems for an infra job."))
    #expect(prompt.contains("For the interview next week"))
    #expect(prompt.contains("You are the reader's companion"))
  }

  @Test func withoutAProfileOrAReasonThePromptLeavesThemOut() async throws {
    let agent = FakeAgent { _ in .reply(Self.stretches([0, 10, 20])) }
    let reader = KeyPointReader(language: "en", profile: "  ", why: nil)

    _ = try await Self.writer(agent).keyPoints(of: try Self.transcript(30), count: .few, for: reader)

    #expect(agent.prompts.first?.contains("USER.md") == false)
    #expect(agent.prompts.first?.contains("they wrote why") == false)
  }

  @Test func anArticlesKeyPointsAreItsParagraphs() async throws {
    let passages = ["# Tail at scale"] + (1...9).map { "Paragraph \($0)." }
    let agent = FakeAgent { _ in
      .reply(
        #"{"keyPoints": [{"passage": 7, "title": "B", "reason": "R"}, {"passage": 2, "title": "A", "reason": "R"}, {"passage": 9, "title": "C", "reason": "R"}]}"#
      )
    }

    let points = try await Self.writer(agent).keyPoints(
      of: .article(passages: passages, title: "Tail"), count: .few, for: Self.reader)

    #expect(points.compactMap(\.passage?.number) == [2, 7, 9])
    #expect(points.first?.passage?.text == "Paragraph 1.")
    #expect(agent.prompts.first?.contains("[7] Paragraph 6.") == true)
  }

  @Test func aPassageThatIsNotThereIsRefused() async throws {
    let agent = FakeAgent { _ in
      .reply(
        #"{"keyPoints": [{"passage": 1, "title": "A", "reason": "R"}, {"passage": 2, "title": "B", "reason": "R"}, {"passage": 40, "title": "C", "reason": "R"}]}"#
      )
    }

    await #expect(
      throws: HostError.invalidRequest(
        "The agent's answer could not be used: a key point names a passage that is not there")
    ) {
      try await Self.writer(agent).keyPoints(
        of: .article(passages: ["One.", "Two.", "Three."], title: "T"), count: .few, for: Self.reader)
    }
  }
}
