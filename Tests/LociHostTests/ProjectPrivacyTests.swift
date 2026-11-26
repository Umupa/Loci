import Foundation
import LociModel
import Testing

@testable import LociHost

/// PJ-S4, PJ-S6, PJ-S9: the main conversation's `loci schedule` and `loci followup` see and change only the
/// chat's timers, and a project kept out of memory is not in the main session any more.
@Suite(.timeLimit(.minutes(1)))
struct ProjectPrivacyTests {
  static func followUp(_ what: String, in session: LocalSession, on host: LocalHost) async throws -> FollowUp {
    let reply = await Background.call(AddFollowUp(.after(minutes: 60), what), from: session, on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(FollowUp.self, from: data)
  }

  static func timers(from session: LocalSession, on host: LocalHost) async throws -> Timers {
    let reply = await Background.call(ListTimers(), from: session, on: host)
    guard case .value(let data)? = reply else { throw HostError.invalidRequest("\(String(describing: reply))") }
    return try JSONDecoder().decode(Timers.self, from: data)
  }

  @Test func eachConversationSeesAndChangesOnlyItsOwnTimers() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, _ in
      let project = try await ProjectScenarioTests.start(host)
      _ = try await host.run(SetProjectRemembered(project, remembered: false))
      let inProject = LocalSession.conversation(.project(project))
      let secret = try await Self.followUp("看看那只基金的赎回费", in: inProject, on: host)
      let chats = try await Self.followUp("周五提醒交房租", in: .conversation(.main), on: host)
      let schedule = try await ProjectBackgroundTests.addSchedule(in: project, on: host)

      let fromMain = try await Self.timers(from: .conversation(.main), on: host)
      let fromProject = try await Self.timers(from: inProject, on: host)
      let cancelled = await Background.call(CancelFollowUp(secret.id), from: .conversation(.main), on: host)
      let removed = await Background.call(RemoveSchedule(schedule.ref), from: .conversation(.main), on: host)

      #expect(fromMain.followUps.map(\.id) == [chats.id])
      #expect(fromMain.schedules.isEmpty)
      #expect(fromProject.followUps.map(\.id) == [secret.id])
      #expect(fromProject.schedules.map(\.ref) == [schedule.ref])
      guard case .failed(.notFound)? = cancelled, case .failed(.notFound)? = removed else {
        throw HostError.invalidRequest("the main conversation changed a project's timer")
      }
      #expect(try await host.timers().followUps.count == 2)
      #expect(try await host.timers().schedules.count == 1)
    }
  }

  @Test func aProjectKeptOutOfMemoryLeavesTheMainSessionItWasToldIn() async throws {
    try await withHost(agent: FakeAgent(provider: .codex)) { host, _, world in
      let project = try await ProjectScenarioTests.start(host)
      _ = try await host.run(SendMessage(to: .main, text: "最近怎样"))
      _ = try #require(await settled(host))
      #expect(world.agent.prompts.last?.contains("盯纳指和几只基金") == true)
      let opened = world.agent.opened.count

      _ = try await host.run(SetProjectRemembered(project, remembered: false))
      _ = try await host.run(SendMessage(to: .main, text: "还有呢"))
      _ = try #require(await settled(host, prompts: 2))

      #expect(world.agent.opened.count == opened + 1)
      #expect(world.agent.prompts.last?.contains("盯纳指和几只基金") == false)
    }
  }
}
