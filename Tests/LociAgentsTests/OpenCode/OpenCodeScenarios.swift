import Foundation
import Testing

@testable import LociAgents

enum OpenCodeScenario {
  static func reply(_ driver: OpenCodeDriver, _ folder: URL) async throws {
    let session = try await driver.open(.init(workingDirectory: folder, permission: .full))
    let turn = try await session.send("Reply with exactly one word: pong")
    await #expect(throws: AgentError.turnInProgress) { try await session.send("And again") }
    let events = await Scenario.watch(turn)
    #expect(events.reply.lowercased().contains("pong"))
    #expect(events.endings == [.completed])
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func tool(_ driver: OpenCodeDriver, _ folder: URL) async throws {
    try Data("The secret word is marmalade.\n".utf8).write(to: folder.appending(path: "notes.txt"))
    let session = try await driver.open(.init(workingDirectory: folder, permission: .full))
    let events = await Scenario.watch(
      try await session.send("Use the read tool to read notes.txt, then tell me the secret word."))
    #expect(events.calls.contains { $0.kind == .read })
    #expect(events.changes.contains(.running))
    #expect(events.outputs.contains { $0.text.contains("marmalade") && !$0.failed })
    #expect(events.reply.contains("marmalade"))
    #expect(events.endings == [.completed])
    await session.close()
  }

  static func permission(_ driver: OpenCodeDriver, _ folder: URL, allow: Bool) async throws {
    let session = try await driver.open(.init(workingDirectory: folder, permission: .ask))
    var asked: [PermissionRequest] = []
    let events = await Scenario.watch(
      try await session.send(
        "Use the bash tool to run exactly: echo loci-42. Do not use other tools. If denied, stop and reply denied.")
    ) { event in
      guard case .permission(let request) = event else { return }
      asked.append(request)
      let role: PermissionRequest.Option.Role = allow ? .allow : .deny
      await session.answer(request.id, with: .chosen(request.options.first { $0.role == role }?.id ?? ""))
    }
    #expect(!asked.isEmpty)
    #expect(asked.first?.options.map(\.role) == [.allow, .allowAlways, .deny])
    #expect(asked.allSatisfy { request in events.calls.contains { $0.id == request.toolCall } })
    if allow {
      #expect(events.outputs.contains { $0.text.contains("loci-42") && !$0.failed })
    } else {
      #expect(!events.outputs.isEmpty)
      #expect(events.outputs.allSatisfy { $0.failed && !$0.text.contains("loci-42") })
    }
    #expect(events.endings == [.completed])
    await session.close()
  }

  static func interrupt(_ driver: OpenCodeDriver, _ folder: URL, asking: Bool) async throws {
    let session = try await driver.open(.init(workingDirectory: folder, permission: asking ? .ask : .full))
    var requests: [PermissionRequest.ID] = []
    var interrupted = false
    let events = await Scenario.watch(try await session.send("Use the bash tool to run exactly: sleep 30")) { event in
      let stop: Bool
      if case .permission(let request) = event {
        requests.append(request.id)
        stop = asking
      } else if case .toolCallChanged(_, .running) = event {
        stop = !asking
      } else {
        stop = false
      }
      if stop, !interrupted {
        interrupted = true
        let started = ContinuousClock.now
        await session.interrupt()
        #expect(ContinuousClock.now - started < .seconds(25))
      }
    }
    #expect(interrupted)
    #expect(events.endings == [.interrupted])
    #expect(requests.allSatisfy { events.contains(.permissionClosed($0)) })
    let next = await Scenario.watch(try await session.send("Reply with exactly one word: pong. Do not use tools."))
    #expect(next.reply.lowercased().contains("pong"))
    #expect(next.endings == [.completed])
    await session.close()
  }

  static func resume(_ driver: OpenCodeDriver, _ folder: URL) async throws {
    let first = try await driver.open(.init(workingDirectory: folder, permission: .full))
    let taught = await Scenario.watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
    #expect(taught.endings == [.completed])
    await first.close()
    let second = try await driver.open(.init(workingDirectory: folder, permission: .full, resume: first.handle))
    #expect(second.handle == first.handle)
    let asked = await Scenario.watch(
      try await second.send("Which word did I ask you to remember? Reply with just that word."))
    #expect(asked.reply.lowercased().contains("quokka"))
    #expect(!asked.reply.contains("OK"))
    #expect(asked.endings == [.completed])
    await second.close()
  }

  static func missingSession(_ driver: OpenCodeDriver, _ folder: URL) async throws {
    await #expect(throws: AgentError.sessionNotFound) {
      _ = try await driver.open(
        .init(
          workingDirectory: folder, permission: .full,
          resume: .init(provider: .opencode, value: "ses_00000000000000000000000000")))
    }
  }

  static func unknownModel(_ driver: OpenCodeDriver, _ folder: URL) async throws {
    do {
      let session = try await driver.open(.init(workingDirectory: folder, model: "nope/none", permission: .full))
      await session.close()
      Issue.record("An unknown model must be rejected")
    } catch {
      guard case .rejected(let message) = error else { throw error }
      #expect(message.contains("nope/none"))
    }
  }
}
