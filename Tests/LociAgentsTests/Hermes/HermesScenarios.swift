import Foundation
import Testing

@testable import LociAgents

enum HermesScenario {
  static let shellPrompt =
    "Use your terminal tool to run exactly this command: echo loci-$((6*7))\nThen tell me what it printed."

  static func reply(_ stage: Stage) async throws {
    let session = try await stage.open()
    #expect(session.handle.provider == .hermes)
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
    #expect(events.calls.contains { $0.kind == .read })
    #expect(events.outputs.contains { $0.text.contains("marmalade") && !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.endings == [.completed])
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func interrupted(_ stage: Stage) async throws {
    let session = try await stage.open()
    let events = await Scenario.watch(
      try await session.send("Use your terminal tool to run exactly this command: sleep 30")
    ) { event in
      if case .toolCallChanged(_, .running) = event { await session.interrupt() }
    }
    #expect(events.endings == [.interrupted])
    #expect(events.last == .ended(.interrupted))
    let next = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
    #expect(next.reply.lowercased().contains("pong"))
    #expect(next.endings == [.completed])
    #expect(next.last == .ended(.completed))
    await session.close()
  }
}
