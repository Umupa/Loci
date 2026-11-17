import Foundation
import LociModel
import Testing

@testable import LociAgents

/// Where Grok keeps its promises differently from Pi: its own tool names, and the four answers ACP offers.
enum GrokScenario {
  static let missingSession = SessionHandle(provider: .grok, value: "019a0000-0000-7000-8000-000000000000")

  static func tool(_ stage: Stage) async throws {
    try Data("The secret word is marmalade.\n".utf8).write(to: stage.folder.appending(path: "notes.txt"))
    let session = try await stage.open()

    let events = await Scenario.watch(
      try await session.send("Read the file notes.txt with your file reading tool, then tell me the secret word."))

    let call = try #require(events.calls.first)
    #expect(call.kind == .read)
    #expect(events.outputs.contains { !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func resumedMissing(_ stage: Stage) async throws {
    await #expect(throws: AgentError.sessionNotFound) { _ = try await stage.open(resume: missingSession) }
  }
}
