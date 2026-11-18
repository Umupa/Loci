import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociHost

/// L-S12, the data: an agent writes a transcript's translation, chapters and highlights.
struct TranscriptAgentTests {
  /// Replies in turn, the last one again once they run out.
  final class Replies: Sendable {
    private let queue: Mutex<[String]>

    init(_ replies: [String]) {
      queue = Mutex(replies)
    }

    func next() -> String {
      queue.withLock { $0.count > 1 ? $0.removeFirst() : ($0.first ?? "") }
    }
  }

  static func transcript(_ count: Int) throws -> Transcript {
    try Transcript(
      language: "en", origin: .platform,
      segments: (0..<count).map { index in
        try Transcript.Segment(start: .seconds(index * 2), end: .seconds(index * 2 + 2), text: "Line \(index).")
      })
  }

  static func writer(_ agent: FakeAgent, translationPiece: Int = 60, provider: Mentor.Provider = .pi)
    -> AgentTranscriptAgent
  {
    AgentTranscriptAgent(
      choice: AgentChoice(provider: provider), agents: { $0 == .pi ? agent : nil }, translationPiece: translationPiece)
  }

  /// Translates by echoing each line of the prompt's JSON with a mark.
  static var translator: FakeAgent {
    FakeAgent { prompt in
      let lines = prompt.matches(of: /"(Line \d+\.)"/).map { "\"译 \($0.output.1)\"" }
      return .reply("Here you go:\n```json\n{\"lines\": [\(lines.joined(separator: ", "))]}\n```")
    }
  }

  @Test func aTranslationHasOneLinePerSentenceInOrder() async throws {
    let translation = try await Self.writer(Self.translator).translate(try Self.transcript(3), into: "zh-Hans")

    #expect(translation.language == "zh-Hans")
    #expect(translation.lines == ["译 Line 0.", "译 Line 1.", "译 Line 2."])
  }

  @Test func aLongTranscriptIsSentInPiecesAndComesBackWhole() async throws {
    let transcript = try Self.transcript(25)
    let agent = Self.translator

    let translation = try await Self.writer(agent, translationPiece: 10).translate(transcript, into: "zh-Hans")

    #expect(agent.prompts.count == 3)
    #expect(translation.fits(transcript))
    #expect(translation.lines.last == "译 Line 24.")
    #expect(agent.opened.allSatisfy { $0.resume == nil })
  }

  @Test func anAnswerWithALineMissingIsAskedForAgain() async throws {
    let replies = Replies([#"{"lines": ["一"]}"#, #"{"lines": ["一", "二"]}"#])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    let translation = try await Self.writer(agent).translate(try Self.transcript(2), into: "zh-Hans")

    #expect(translation.lines == ["一", "二"])
    #expect(agent.prompts.count == 2)
  }

  @Test func twoAnswersThatDoNotFitFailSayingWhy() async throws {
    let agent = FakeAgent { _ in .reply(#"{"lines": ["一"]}"#) }

    await #expect(throws: HostError.invalidRequest("The agent's answer could not be used: 1 lines came back for 2")) {
      try await Self.writer(agent).translate(try Self.transcript(2), into: "zh-Hans")
    }
    #expect(agent.prompts.count == 2)
  }

  @Test func anAnswerWithoutJSONIsAskedForAgain() async throws {
    let replies = Replies(["Sorry, I cannot.", #"{"lines": ["一"]}"#])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    #expect(try await Self.writer(agent).translate(try Self.transcript(1), into: "zh").lines == ["一"])
  }

  @Test func aMissingAgentIsSaidAtOnce() async throws {
    await #expect(throws: HostError.invalidRequest("grok is not installed on this Mac.")) {
      try await Self.writer(Self.translator, provider: .grok).translate(try Self.transcript(1), into: "zh")
    }
  }

  @Test func anOutlineHasChaptersInOrderAndHighlightsWithReasons() async throws {
    let agent = FakeAgent { _ in
      .reply(
        """
        {"chapters": [{"start": 0, "title": "Why"}, {"start": 6, "title": "How"}],
         "highlights": [{"start": 2, "end": 8, "title": "The trick", "reason": "It explains the core idea."}]}
        """)
    }

    let outline = try await Self.writer(agent).outline(try Self.transcript(5), title: "Talk")

    #expect(outline.chapters.map(\.title) == ["Why", "How"])
    #expect(outline.chapters.map(\.start) == [.zero, .seconds(6)])
    #expect(outline.highlights.map(\.span) == [try TimeSpan(start: .seconds(2), end: .seconds(8))])
    #expect(agent.prompts.first?.contains("[2.0-4.0] Line 1.") == true)
    #expect(agent.prompts.first?.contains("\"Talk\"") == true)
  }

  @Test func chaptersOutOfOrderAreAskedForAgain() async throws {
    let replies = Replies([
      #"{"chapters": [{"start": 6, "title": "B"}, {"start": 0, "title": "A"}], "highlights": []}"#,
      #"{"chapters": [{"start": 0, "title": "A"}], "highlights": []}"#,
    ])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    #expect(try await Self.writer(agent).outline(try Self.transcript(5), title: "T").chapters.map(\.title) == ["A"])
    #expect(agent.prompts.count == 2)
  }

  @Test func aHighlightPastTheEndIsRefused() async throws {
    let agent = FakeAgent { _ in
      .reply(#"{"chapters": [], "highlights": [{"start": 2, "end": 99, "title": "T", "reason": "R"}]}"#)
    }

    await #expect(
      throws: HostError.invalidRequest("The agent's answer could not be used: a highlight ends at 99.0s, after the end")
    ) {
      try await Self.writer(agent).outline(try Self.transcript(5), title: "T")
    }
  }

  @Test func piecesOfAnOutlineAreJoinedWithoutRepeatingAChapter() async throws {
    let agent = FakeAgent { prompt in
      prompt.contains("part 1 of 2")
        ? .reply(#"{"chapters": [{"start": 0, "title": "A"}], "highlights": []}"#)
        : .reply(
          #"{"chapters": [{"start": 400, "title": "A"}, {"start": 402, "title": "B"}], "highlights": [{"start": 404, "end": 406, "title": "T", "reason": "R"}]}"#
        )
    }

    let outline = try await Self.writer(agent).outline(try Self.transcript(250), title: "T")

    #expect(outline.chapters.map(\.title) == ["A", "B"])
    #expect(outline.highlights.count == 1)
  }
}
