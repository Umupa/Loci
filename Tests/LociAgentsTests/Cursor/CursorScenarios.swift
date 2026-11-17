import Foundation
import Testing

@testable import LociAgents

enum CursorScenario {
  static func resumed(_ stage: Stage) async throws {
    let first = try await stage.open()
    let taught = await Scenario.watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
    #expect(taught.last == .ended(.completed))
    await first.close()
    let second = try await stage.open(resume: first.handle)
    #expect(second.handle == first.handle)
    let events = await Scenario.watch(
      try await second.send("Which word did I ask you to remember? Reply with just that word."))
    #expect(events.reply.lowercased().contains("quokka"))
    #expect(!events.reply.contains("Old text must not appear in the new turn."))
    #expect(events.endings == [.completed])
    #expect(events.last == .ended(.completed))
    await second.close()
  }

  static func reply(_ stage: Stage) async throws {
    let session = try await stage.open()
    let turn = try await session.send("Reply with exactly one word: pong")
    await #expect(throws: AgentError.turnInProgress) { try await session.send("And again") }
    let events = await Scenario.watch(turn)
    #expect(events.reply.lowercased().contains("pong"))
    #expect(events.endings == [.completed])
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func tool(_ stage: Stage) async throws {
    try Data("The secret word is marmalade.\n".utf8).write(to: stage.folder.appending(path: "notes.txt"))
    let session = try await stage.open()
    let events = await Scenario.watch(
      try await session.send("Read the file notes.txt with your file reading tool, then tell me the secret word."))
    let call = try #require(events.calls.first)
    #expect(call.kind == .read)
    #expect(events.outputs.contains { $0.text.contains("marmalade") && !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.last == .ended(.completed))
    await session.close()
  }
}
