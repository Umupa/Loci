import Foundation
import LociModel
import Testing

@testable import LociAgents

enum ClaudeCodeScenario {
  /// The id every new session gets, so recordings replay with the same one.
  static let sessionID = "c13ce784-7a6a-44df-9607-6fb137aca546"
  static let shell = "Use Bash to run exactly: echo loci-$((6*7)). Do not use any other tools. Report its output."

  static func reply(_ stage: Stage) async throws {
    let session = try await stage.open()
    let turn = try await session.send("Reply with exactly one word: pong")
    await #expect(throws: AgentError.turnInProgress) { try await session.send("Again") }
    let events = await Scenario.watch(turn)
    #expect(events.reply.lowercased().contains("pong"))
    #expect(events.filter { if case .text = $0 { true } else { false } }.count >= 1)
    #expect(events.endings == [.completed])
    #expect(events.last == .ended(.completed))
    #expect(events.contains { if case .context = $0 { true } else { false } })
    await session.close()
    await #expect(throws: AgentError.rejected("Session closed")) { try await session.send("Again") }
  }

  static func tool(_ stage: Stage) async throws {
    try Data("The secret word is marmalade.\n".utf8).write(to: stage.folder.appending(path: "notes.txt"))
    let session = try await stage.open()
    let events = await Scenario.watch(
      try await session.send("Use Read to read notes.txt, then tell me the secret word. Do not use any other tools."))
    #expect(events.calls.contains { $0.name == "Read" && $0.kind == .read })
    #expect(events.outputs.contains { $0.text.contains("marmalade") && !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.endings == [.completed])
    await session.close()
  }

  static func interrupted(_ stage: Stage) async throws {
    let session = try await stage.open()
    let deadline = Task {
      try? await Task.sleep(for: .seconds(90))
      if !Task.isCancelled { await session.interrupt() }
    }
    defer { deadline.cancel() }
    var sawProgress = false
    let events = await Scenario.watch(
      try await session.send(
        "Use Bash to run exactly: python3 -c 'import time; time.sleep(60)'. Run it in the foreground with timeout 120000."
      )
    ) { event in
      if case .permission(let request) = event { await session.answer(request.id, with: .chosen("allow")) }
      if case .toolCallChanged(_, .running) = event {
        sawProgress = true
        let started = ContinuousClock.now
        await session.interrupt()
        #expect(ContinuousClock.now - started < .seconds(25))
      }
    }
    #expect(sawProgress)
    #expect(events.endings == [.interrupted])
    let next = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
    #expect(next.reply.lowercased().contains("pong"))
    #expect(next.endings == [.completed])
    await session.close()
  }

  static func resumed(_ stage: Stage) async throws {
    let first = try await stage.open()
    let events = await Scenario.watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
    #expect(events.endings == [.completed])
    await first.close()
    let second = try await stage.open(resume: first.handle)
    #expect(second.handle == first.handle)
    let next = await Scenario.watch(
      try await second.send("Which word did I ask you to remember? Reply with just that word."))
    #expect(next.reply.lowercased().contains("quokka"))
    #expect(next.endings == [.completed])
    await second.close()
  }

  static func missing(_ stage: Stage) async throws {
    let handle = SessionHandle(provider: .claudeCode, value: "019a0000-0000-7000-8000-000000000000")
    await #expect(throws: AgentError.sessionNotFound) { try await stage.open(resume: handle) }
  }
}
