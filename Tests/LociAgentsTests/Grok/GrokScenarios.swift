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

  static func permissionAllowed(_ stage: Stage) async throws {
    let session = try await stage.open(.ask)
    var asked: [PermissionRequest] = []

    let events = await Scenario.watch(try await session.send(Scenario.shellPrompt)) { event in
      guard case .permission(let request) = event else { return }
      asked.append(request)
      await session.answer(request.id, with: .chosen(request.options.first { $0.role == .allow }?.id ?? ""))
    }

    let request = try #require(asked.first)
    #expect(request.title.contains("echo loci-"))
    #expect(request.toolCall == events.calls.first?.id)
    #expect(Set(request.options.map(\.role)) == [.allow, .allowAlways, .deny, .denyAlways])
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

  static func resumedMissing(_ stage: Stage) async throws {
    await #expect(throws: AgentError.sessionNotFound) { _ = try await stage.open(resume: missingSession) }
  }
}
