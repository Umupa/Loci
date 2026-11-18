import Foundation
import LociAgents
import LociModel
import Testing

@testable import LociHost

/// L-S1: the app can quit at any moment, with no chance to tidy up, and what the person sent is still there.
@Suite(.timeLimit(.minutes(1)))
struct QuitScenarioTests {
  static let hi = Message.Body.prompt(Prompt(text: "在吗", purpose: .chat))

  /// Starts a host on `place`, sends "在吗" and gives the host while Loci is still answering. The host is
  /// never closed before the next one starts, as when the app is quit.
  private func quitWhileAnswering(
    at place: Place, _ world: TestWorld, _ agent: ManualAgent, answering: Bool
  ) async throws -> LocalHost {
    let host = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment(running: { _ in agent }))
    _ = try await host.run(SendMessage(to: .main, text: "在吗"))
    if answering {
      #expect(await working(host))
    } else {
      #expect(await waitingToOpen(agent))
    }
    return host
  }

  @Test func aMessageSentStaysAfterQuittingInTheMiddleOfTheAnswer() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let agent = ManualAgent()
    let quit = try await quitWhileAnswering(at: place, world, agent, answering: true)

    let reopened = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment(running: { _ in agent }))
    let after = try await reopened.conversation(.main)
    await reopened.close()
    await quit.close()

    #expect(after.bodies == [Self.hi, .ended(.interrupted)])
  }

  @Test func aMessageSentStaysAfterQuittingBeforeTheAgentStarted() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let agent = ManualAgent(opensFreely: 0)
    let quit = try await quitWhileAnswering(at: place, world, agent, answering: false)

    let reopened = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment(running: { _ in ManualAgent() }))
    let after = try await reopened.conversation(.main)
    await reopened.close()
    await agent.letOpen()
    await quit.close()

    #expect(after.bodies == [Self.hi, .ended(.interrupted)])
  }

  /// The conversation goes on after the quit, and the stopped turn is part of what came before.
  @Test func theConversationGoesOnAfterQuittingInTheMiddleOfTheAnswer() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let agent = ManualAgent()
    let quit = try await quitWhileAnswering(at: place, world, agent, answering: true)

    let next = ManualAgent()
    let reopened = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment(running: { _ in next }))
    _ = try await reopened.run(SendMessage(to: .main, text: "还在吗"))
    #expect(await working(reopened))
    await next.sessions.last?.finish()
    let done = await settled(reopened, prompts: 2)
    await reopened.close()
    await quit.close()

    #expect(
      done?.bodies == [
        Self.hi, .ended(.interrupted), .prompt(Prompt(text: "还在吗", purpose: .chat)), .reply("Waiting"),
      ])
  }

  /// A turn that ran to its end is not taken for one cut short.
  @Test func aFinishedTurnIsNotMarkedStoppedAfterARestart() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let agent = ManualAgent()
    let first = try await quitWhileAnswering(at: place, world, agent, answering: true)
    await agent.sessions.last?.finish()
    _ = await settled(first)
    await first.close()

    let reopened = try await LocalHost.start(
      root: place.root, database: place.database, environment: world.environment(running: { _ in agent }))
    let after = try await reopened.conversation(.main)
    await reopened.close()

    #expect(after.bodies == [Self.hi, .reply("Waiting")])
  }

  private func waitingToOpen(_ agent: ManualAgent) async -> Bool {
    for _ in 0..<500 {
      if await agent.waitingToOpen > 0 { return true }
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }
}
