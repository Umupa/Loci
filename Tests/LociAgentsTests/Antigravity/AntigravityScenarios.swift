import Foundation
import LociModel
import Testing

@testable import LociAgents

enum AntigravityScenario {
  static let shellPrompt = "Run this shell command exactly: echo loci-$((6*7)). Then tell me its output."

  static func tool(_ stage: Stage) async throws {
    try Data("The secret word is marmalade.\n".utf8).write(to: stage.folder.appending(path: "notes.txt"))
    let session = try await stage.open()
    let events = await Scenario.watch(
      try await session.send("Read notes.txt with your file reading tool, then tell me the secret word."))
    #expect(events.calls.contains { $0.kind == .read })
    #expect(events.outputs.contains { !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func resumedMissing(_ stage: Stage) async throws {
    let missing = SessionHandle(provider: .antigravity, value: "019a0000-0000-7000-8000-000000000000")
    await #expect(throws: AgentError.sessionNotFound) { _ = try await stage.open(resume: missing) }
  }

  static func unknownModel(_ stage: Stage) async throws {
    await #expect(throws: AgentError.self) { _ = try await stage.open(model: "nope/none") }
  }
}
