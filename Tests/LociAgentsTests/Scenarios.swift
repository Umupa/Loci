import Foundation
import LociModel
import Testing

@testable import LociAgents

/// Where a scenario plays out: against the real agent or against a recording of it.
struct Stage {
  let driver: any AgentDriver
  let folder: URL

  func open(
    _ permission: Mentor.Permission = .full, model: String? = nil, resume: SessionHandle? = nil
  ) async throws(AgentError) -> any AgentSession {
    try await driver.open(
      SessionConfiguration(workingDirectory: folder, model: model, permission: permission, resume: resume))
  }
}

extension [AgentEvent] {
  var reply: String {
    self.reduce(into: "") { text, event in
      if case .text(let more) = event { text += more }
    }
  }

  var calls: [ToolCall] {
    compactMap { event in
      if case .toolCall(let call) = event { call } else { nil }
    }
  }

  var changes: [ToolCall.Change] {
    compactMap { event in
      if case .toolCallChanged(_, let change) = event { change } else { nil }
    }
  }

  var outputs: [(text: String, failed: Bool)] {
    changes.compactMap { change in
      if case .finished(let output, let failed) = change { (output, failed) } else { nil }
    }
  }

  var endings: [TurnEnd] {
    compactMap { event in
      if case .ended(let end) = event { end } else { nil }
    }
  }
}

/// The behaviours the driver promises. Each runs unchanged against the real Pi and against its recording.
enum Scenario {
  static let missingSession = SessionHandle(provider: .pi, value: "019a0000-0000-7000-8000-000000000000")

  /// Collects a turn's events, calling `react` on each one as it arrives.
  static func watch(_ turn: Turn, react: (AgentEvent) async -> Void = { _ in }) async -> [AgentEvent] {
    var seen: [AgentEvent] = []
    for await event in turn.events {
      seen.append(event)
      await react(event)
    }
    return seen
  }

  static func reply(_ stage: Stage) async throws {
    let session = try await stage.open()
    let turn = try await session.send("Reply with exactly one word: pong")
    await #expect(throws: AgentError.turnInProgress) { try await session.send("And again") }

    let events = await watch(turn)

    #expect(events.reply.lowercased().contains("pong"))
    #expect(events.endings == [.completed])
    #expect(events.last == .ended(.completed))
    #expect(events.contains { if case .context = $0 { true } else { false } })
    await session.close()
  }

  static func tool(_ stage: Stage) async throws {
    try Data("The secret word is marmalade.\n".utf8).write(to: stage.folder.appending(path: "notes.txt"))
    let session = try await stage.open()

    let events = await watch(
      try await session.send("Use the read tool to read notes.txt, then tell me the secret word."))

    let call = try #require(events.calls.first)
    #expect(call.name == "read")
    #expect(call.kind == .read)
    #expect(events.changes.contains(.running))
    #expect(events.outputs.contains { $0.text.contains("marmalade") && !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static let shellPrompt =
    "Use the bash tool to run exactly this command: echo loci-$((6*7))\nThen tell me what it printed."

  static func permissionAllowed(_ stage: Stage) async throws {
    let session = try await stage.open(.ask)
    var asked: [PermissionRequest] = []

    let events = await watch(try await session.send(shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked.append(request)
      await session.answer(request.id, with: .chosen(request.options.first { $0.role == .allow }?.id ?? ""))
    }

    let request = try #require(asked.first)
    #expect(request.title == "bash")
    #expect(request.toolCall == events.calls.first?.id)
    #expect(request.options.map(\.role) == [.allow, .deny])
    #expect(events.outputs.contains { $0.text.contains("loci-42") && !$0.failed })
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func permissionDenied(_ stage: Stage) async throws {
    let session = try await stage.open(.ask)
    var asked = 0

    let events = await watch(try await session.send(shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked += 1
      await session.answer(request.id, with: .chosen(request.options.first { $0.role == .deny }?.id ?? ""))
    }

    #expect(asked >= 1)
    #expect(!events.outputs.isEmpty)
    #expect(events.outputs.allSatisfy { $0.failed && !$0.text.contains("loci-42") })
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func interrupted(_ stage: Stage) async throws {
    let session = try await stage.open()
    let started = ContinuousClock.now

    let events = await watch(try await session.send("Use the bash tool to run exactly this command: sleep 30")) {
      if case .toolCallChanged(_, .running) = $0 { await session.interrupt() }
    }

    #expect(events.endings == [.interrupted])
    #expect(events.last == .ended(.interrupted))
    #expect(ContinuousClock.now - started < .seconds(25))

    let next = await watch(try await session.send("Reply with exactly one word: pong"))
    #expect(next.reply.lowercased().contains("pong"))
    #expect(next.last == .ended(.completed))
    await session.close()
  }

  static func interruptedWhileAsking(_ stage: Stage) async throws {
    let session = try await stage.open(.ask)
    var asked: [PermissionRequest.ID] = []

    let events = await watch(try await session.send(shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked.append(request.id)
      await session.interrupt()
    }

    let request = try #require(asked.first)
    #expect(events.contains(.permissionClosed(request)))
    #expect(!events.outputs.contains { $0.text.contains("loci-42") })
    #expect(events.last == .ended(.interrupted))
    await session.close()
  }

  static func resumed(_ stage: Stage) async throws {
    let first = try await stage.open()
    let taught = await watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
    #expect(taught.last == .ended(.completed))
    await first.close()

    let second = try await stage.open(resume: first.handle)
    #expect(second.handle == first.handle)
    let asked = await watch(
      try await second.send("Which word did I ask you to remember? Reply with just that word."))

    #expect(asked.reply.lowercased().contains("quokka"))
    #expect(asked.last == .ended(.completed))
    await second.close()
  }

  static func resumedMissing(_ stage: Stage) async throws {
    await #expect(throws: AgentError.sessionNotFound) { _ = try await stage.open(resume: missingSession) }
  }

  static func unknownModel(_ stage: Stage) async throws {
    do {
      _ = try await stage.open(model: "nope/none")
      Issue.record("opening with an unknown model should fail")
    } catch .exited(let code, let said) {
      #expect(code == 1)
      #expect(said.contains("nope/none"))
    }
  }
}
