import Foundation
import LociModel
import LociStore
import Testing

@testable import LociHost

/// WT-S8: a card with a deadline folds away once it passes, on every deck that shows it, and nothing more can
/// be done with it.
@Suite(.timeLimit(.minutes(1)))
struct NextUpDeadlineTests {
  static func add(_ what: String, deadline: Timestamp?, on host: LocalHost) async -> LocalReply? {
    await Background.call(
      AddNextUp(what, asking: "要调整吗？", deadline: deadline), from: .conversation(.main), on: host)
  }

  @Test func aCardFoldsAwayAtItsDeadlineAndTheDecksAreToldAtThatMinute() async throws {
    try await withHost { host, _, world in
      let deadline = Watching.minutes(30, after: world.now)
      guard case .value(let data)? = await Self.add("国常会稳市", deadline: deadline, on: host) else {
        Issue.record("the card was refused")
        return
      }
      let card = try JSONDecoder().decode(NextUp.self, from: data)
      #expect(card.deadline == deadline)
      world.tick()
      let deck = host.subscribe(WatchNextUps(of: .chat))
      _ = await value(deck) { $0.count == 1 }

      world.advance(minutes: 30)
      world.tick()

      #expect(await value(deck) { $0.isEmpty } != nil)
      await #expect(throws: HostError.self) {
        _ = try await host.setNextUp(SetNextUp(card.id, .keep, version: card.version))
      }
    }
  }

  @Test func aDeadlineThatPassedIsRefused() async throws {
    try await withHost { host, _, world in
      let reply = await Self.add("迟了", deadline: Watching.minutes(-1, after: world.now), on: host)
      let deck = try await NextUpScenarioTests.deck(host)
      #expect(WatchDepthTests.refusal(reply)?.contains("deadline") == true)
      #expect(deck.isEmpty)
    }
  }
}
