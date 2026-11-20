import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociHost

/// L-S12, the data: an agent writes a transcript's translation and chapters.
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

  static func writer(_ agent: FakeAgent, provider: Provider = .pi) -> AgentTranscriptAgent {
    AgentTranscriptAgent(runtime: Runtime(provider: provider), agents: { $0 == .pi ? agent : nil })
  }

  static func lines(_ count: Int) -> [String] {
    (0..<count).map { "Line \($0)." }
  }

  /// Translates by echoing each line of the prompt's JSON with a mark.
  static var translator: FakeAgent {
    FakeAgent { prompt in
      let lines = prompt.matches(of: /"(Line \d+\.)"/).map { "\"译 \($0.output.1)\"" }
      return .reply("Here you go:\n```json\n{\"lines\": [\(lines.joined(separator: ", "))]}\n```")
    }
  }

  @Test func aTranslationHasOneLinePerSentenceInOrder() async throws {
    let agent = Self.translator
    let lines = try await Self.writer(agent).translate(lines: Self.lines(3), into: "zh-Hans")

    #expect(lines == ["译 Line 0.", "译 Line 1.", "译 Line 2."])
    #expect(agent.opened.allSatisfy { $0.resume == nil })
  }

  @Test func anAnswerWithALineMissingIsAskedForAgain() async throws {
    let replies = Replies([#"{"lines": ["一"]}"#, #"{"lines": ["一", "二"]}"#])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    let lines = try await Self.writer(agent).translate(lines: Self.lines(2), into: "zh-Hans")

    #expect(lines == ["一", "二"])
    #expect(agent.prompts.count == 2)
  }

  @Test func twoAnswersThatDoNotFitFailSayingWhy() async throws {
    let agent = FakeAgent { _ in .reply(#"{"lines": ["一"]}"#) }

    await #expect(throws: HostError.invalidRequest("The agent's answer could not be used: 1 lines came back for 2")) {
      try await Self.writer(agent).translate(lines: Self.lines(2), into: "zh-Hans")
    }
    #expect(agent.prompts.count == 2)
  }

  @Test func anAnswerWithoutJSONIsAskedForAgain() async throws {
    let replies = Replies(["Sorry, I cannot.", #"{"lines": ["一"]}"#])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    #expect(try await Self.writer(agent).translate(lines: Self.lines(1), into: "zh") == ["一"])
  }

  @Test func aMissingAgentIsSaidAtOnce() async throws {
    await #expect(throws: HostError.invalidRequest("grok is not installed on this Mac.")) {
      try await Self.writer(Self.translator, provider: .grok).translate(lines: Self.lines(1), into: "zh")
    }
  }

  @Test func anOutlineHasChaptersInOrder() async throws {
    let agent = FakeAgent { _ in .reply(#"{"chapters": [{"start": 0, "title": "Why"}, {"start": 6, "title": "How"}]}"#)
    }

    let outline = try await Self.writer(agent).outline(try Self.transcript(5), title: "Talk")

    #expect(outline.chapters.map(\.title) == ["Why", "How"])
    #expect(outline.chapters.map(\.start) == [.zero, .seconds(6)])
    #expect(agent.prompts.first?.contains("[2.0-4.0] Line 1.") == true)
    #expect(agent.prompts.first?.contains("\"Talk\"") == true)
    #expect(agent.prompts.first?.contains("keyPoints") == false)
  }

  @Test func chaptersOutOfOrderAreAskedForAgain() async throws {
    let replies = Replies([
      #"{"chapters": [{"start": 6, "title": "B"}, {"start": 0, "title": "A"}]}"#,
      #"{"chapters": [{"start": 0, "title": "A"}]}"#,
    ])
    let agent = FakeAgent { _ in .reply(replies.next()) }

    #expect(try await Self.writer(agent).outline(try Self.transcript(5), title: "T").chapters.map(\.title) == ["A"])
    #expect(agent.prompts.count == 2)
  }

  @Test func piecesOfAnOutlineAreJoinedWithoutRepeatingAChapter() async throws {
    let agent = FakeAgent { prompt in
      prompt.contains("part 1 of 2")
        ? .reply(#"{"chapters": [{"start": 0, "title": "A"}]}"#)
        : .reply(#"{"chapters": [{"start": 400, "title": "A"}, {"start": 402, "title": "B"}]}"#)
    }

    let outline = try await Self.writer(agent).outline(try Self.transcript(250), title: "T")

    #expect(outline.chapters.map(\.title) == ["A", "B"])
  }
}
