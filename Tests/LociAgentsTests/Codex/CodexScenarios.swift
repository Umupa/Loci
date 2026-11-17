import Foundation
import LociModel
import Testing

@testable import LociAgents

struct CodexStage {
  let driver: CodexDriver
  let folder: URL

  func open(_ permission: Mentor.Permission = .full, resume: SessionHandle? = nil) async throws(AgentError)
    -> any AgentSession
  {
    try await driver.open(.init(workingDirectory: folder, permission: permission, resume: resume))
  }
}

enum CodexScenario {
  static func reply(_ stage: CodexStage) async throws {
    let session = try await stage.open()
    let events = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
    #expect(events.reply.lowercased().contains("pong"))
    #expect(events.endings == [.completed])
    #expect(events.contains { if case .context = $0 { true } else { false } })
    await session.close()
  }

  static func tool(_ stage: CodexStage) async throws {
    let session = try await stage.open()
    let events = await Scenario.watch(
      try await session.send("Run exactly this shell command: printf loci-42. Then tell me its output."))
    #expect(events.calls.contains { $0.kind == .execute })
    #expect(events.changes.contains(.running))
    #expect(events.outputs.contains { $0.text.contains("loci-42") && !$0.failed })
    #expect(events.endings == [.completed])
    await session.close()
  }

  static let shellPrompt =
    "Run exactly this shell command: touch approval-marker. Do not use any other tools or commands."

  static func permission(_ stage: CodexStage, allow: Bool) async throws {
    let session = try await stage.open(.ask)
    var asked = 0
    let events = await Scenario.watch(try await session.send(shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked += 1
      #expect(request.toolCall != nil)
      await session.answer(request.id, with: .chosen(allow ? "accept" : "decline"))
      await session.answer(request.id, with: .chosen("accept"))
    }
    #expect(asked > 0)
    #expect(events.outputs.contains { !$0.failed } == allow)
    #expect(events.endings == [.completed])
    await session.close()
  }

  static func interrupted(_ stage: CodexStage) async throws {
    let session = try await stage.open()
    let events = await Scenario.watch(
      try await session.send("Run exactly this shell command: sleep 30")
    ) { event in
      if case .toolCallChanged(_, .running) = event { await session.interrupt() }
    }
    #expect(events.endings == [.interrupted])
    let next = await Scenario.watch(try await session.send("Reply with exactly one word: pong"))
    #expect(next.reply.lowercased().contains("pong"))
    #expect(next.endings == [.completed])
    await session.close()
  }

  static func interruptedWhileAsking(_ stage: CodexStage) async throws {
    let session = try await stage.open(.ask)
    var asked: PermissionRequest.ID?
    let events = await Scenario.watch(try await session.send(shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked = request.id
      await session.interrupt()
    }
    let id = try #require(asked)
    #expect(events.filter { if case .permission = $0 { true } else { false } }.count == 1)
    #expect(events.contains(.permissionClosed(id)))
    #expect(events.endings == [.interrupted])
    #expect(!FileManager.default.fileExists(atPath: stage.folder.appending(path: "approval-marker").path))
    await session.close()
  }

  static func resumed(_ stage: CodexStage) async throws {
    let first = try await stage.open()
    let taught = await Scenario.watch(try await first.send("Remember this word: quokka. Reply with exactly: OK"))
    #expect(taught.endings == [.completed])
    await first.close()
    let second = try await stage.open(resume: first.handle)
    #expect(second.handle == first.handle)
    let events = await Scenario.watch(
      try await second.send("Which word did I ask you to remember? Reply with just that word."))
    #expect(events.reply.lowercased().contains("quokka"))
    #expect(events.endings == [.completed])
    await second.close()
  }

  static func missing(_ stage: CodexStage) async throws {
    await #expect(throws: AgentError.sessionNotFound) {
      try await stage.open(resume: .init(provider: .codex, value: "019a0000-0000-7000-8000-000000000000"))
    }
  }
}
