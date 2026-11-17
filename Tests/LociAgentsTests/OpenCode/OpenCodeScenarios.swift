import Foundation
import Testing

@testable import LociAgents

enum OpenCodeScenario {
  static func reply(_ stage: Stage) async throws {
    let session = try await stage.open()
    #expect(session is AcpSession)
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
      try await session.send("Use the read tool to read notes.txt, then tell me the secret word."))
    #expect(events.calls.contains { $0.kind == .read })
    #expect(events.changes.contains(.running))
    #expect(events.outputs.contains { $0.text.contains("marmalade") && !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.endings == [.completed])
    await session.close()
  }

  static func interrupt(_ stage: Stage) async throws {
    let session = try await stage.open()
    var interrupted = false
    let events = await Scenario.watch(try await session.send("Use the bash tool to run exactly: sleep 30")) { event in
      guard case .toolCallChanged(_, .running) = event else { return }
      if !interrupted {
        interrupted = true
        let started = ContinuousClock.now
        await session.interrupt()
        #expect(ContinuousClock.now - started < .seconds(25))
      }
    }
    #expect(interrupted)
    #expect(events.endings == [.interrupted])
    let next = await Scenario.watch(try await session.send("Reply with exactly one word: pong. Do not use tools."))
    #expect(next.reply.lowercased().contains("pong"))
    #expect(next.endings == [.completed])
    await session.close()
  }

  static func resume(_ stage: Stage) async throws {
    let first = try await stage.open()
    let taught = await Scenario.watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
    #expect(taught.endings == [.completed])
    await first.close()
    let second = try await stage.open(resume: first.handle)
    #expect(second.handle == first.handle)
    let asked = await Scenario.watch(
      try await second.send("Which word did I ask you to remember? Reply with just that word."))
    #expect(asked.reply.lowercased().contains("quokka"))
    #expect(!asked.reply.contains("OK"))
    #expect(asked.endings == [.completed])
    await second.close()
  }

  static func missingSession(_ stage: Stage) async throws {
    await #expect(throws: AgentError.sessionNotFound) {
      _ = try await stage.open(resume: .init(provider: .opencode, value: "ses_00000000000000000000000000"))
    }
  }

  static func unknownModel(_ stage: Stage) async throws {
    do {
      let session = try await stage.open(model: "nope/none")
      await session.close()
      Issue.record("An unknown model must be rejected")
    } catch {
      guard case .rejected(let message) = error else { throw error }
      #expect(message.contains("nope/none"))
    }
  }
}
