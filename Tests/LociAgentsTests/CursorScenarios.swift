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

  static func permissionAllowed(_ stage: Stage) async throws {
    let session = try await stage.open(.ask)
    var asked: [PermissionRequest] = []
    let events = await Scenario.watch(try await session.send(Scenario.shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked.append(request)
      await session.answer(request.id, with: .chosen(request.options.first { $0.role == .allow }?.id ?? ""))
    }
    let request = try #require(asked.first)
    #expect(request.toolCall == events.calls.first?.id)
    #expect(request.options.contains { $0.role == .allow })
    #expect(request.options.contains { $0.role == .deny })
    #expect(events.outputs.contains { $0.text.contains("loci-42") && !$0.failed })
    #expect(events.last == .ended(.completed))
    await session.close()
  }

  static func permissionDenied(_ stage: Stage) async throws {
    let session = try await stage.open(.ask)
    var asked = 0
    let events = await Scenario.watch(try await session.send(Scenario.shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked += 1
      await session.answer(request.id, with: .chosen(request.options.first { $0.role == .deny }?.id ?? ""))
    }
    #expect(asked >= 1)
    #expect(!events.outputs.contains { $0.text.contains("loci-42") })
    #expect(events.last == .ended(.completed))
    await session.close()
  }
}
