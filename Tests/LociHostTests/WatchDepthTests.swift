import Foundation
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// WT-S10: what a finding's run sets goes one level further down and never past its deadline, two levels at
/// most; the earliest deadline goes first, even while the person talks; and a home's findings start at most
/// `Worker.wakesPerHour` runs an hour.
@Suite(.timeLimit(.minutes(1)))
struct WatchDepthTests {
  /// What each `loci` call of a run answered, in order.
  final class Said: Sendable {
    private let replies = Mutex<[LocalReply?]>([])
    var all: [LocalReply?] { replies.withLock { $0 } }
    func add(_ reply: LocalReply?) { replies.withLock { $0.append(reply) } }
  }

  static func refusal(_ reply: LocalReply?) -> String? {
    if case .failed(let error)? = reply { "\(error)" } else { nil }
  }

  @Test func aFollowUpOfAFindingsRunKeepsItsDeadlineAndCannotGoPastIt() async throws {
    let said = Said()
    let companion = WatchCompanion { prompt, run, host in
      guard prompt.hasPrefix(WatchCompanion.prefix) else { return }
      said.add(await Background.call(AddFollowUp(.after(minutes: 10), "再看看"), from: run, on: host))
      let later = Timestamp.parseISO8601("2030-01-02T00:00:00+08:00")
      said.add(await Background.call(AddFollowUp(.after(minutes: 20), "更晚", deadline: later), from: run, on: host))
    }
    try await withWatchHost(model: .discarding(), companion: companion) { host, _, world in
      let deadline = Watching.minutes(60, after: world.now)
      try Watching.raise("国常会稳市", deadline: deadline, on: host, world)
      await host.worker.consider()
      await host.worker.quiet(.chat)

      let followUps = try host.database.followUps()
      #expect(followUps.map(\.what) == ["再看看"])
      #expect(followUps.first?.deadline == deadline)
      #expect(followUps.first?.depth == 2)
      #expect(Self.refusal(said.all.last ?? nil)?.contains("cannot be later") == true)
    }
  }

  @Test func aRunTwoLevelsDownIsToldItCannotSetAnotherFollowUp() async throws {
    let said = Said()
    let companion = WatchCompanion { prompt, run, host in
      said.add(await Background.call(AddFollowUp(.after(minutes: 10), "再看看"), from: run, on: host))
    }
    try await withWatchHost(model: .discarding(), companion: companion) { host, _, world in
      try Watching.raise("国常会稳市", deadline: Watching.minutes(60, after: world.now), on: host, world)
      await host.worker.consider()
      await host.worker.quiet(.chat)
      world.advance(minutes: 10)
      world.tick()
      #expect(try await Background.ran(1, starting: Background.followUp, on: host, world))

      #expect(Self.refusal(said.all.first ?? nil) == nil)
      #expect(Self.refusal(said.all.last ?? nil)?.contains("levels down") == true)
      #expect(try host.database.followUps().isEmpty)
    }
  }

  @Test func theEarliestDeadlineGoesFirstEvenWhileThePersonTalks() async throws {
    let companion = WatchCompanion(main: .hang)
    try await withWatchHost(model: .discarding(), companion: companion) { host, _, world in
      _ = try await host.run(SendMessage(to: .main, text: "在吗"))
      try Watching.raise("晚的", deadline: Watching.minutes(90, after: world.now), on: host, world)
      try Watching.raise("早的", deadline: Watching.minutes(30, after: world.now), on: host, world)
      await host.worker.consider()
      await host.worker.quiet(.chat)
      await host.worker.consider()
      await host.worker.quiet(.chat)

      let runs = Background.prompts(world, starting: WatchCompanion.prefix)
      #expect(runs.count == 2)
      #expect(runs.first?.contains("早的") == true)
    }
  }

  @Test func aFindingWhoseDeadlinePassedIsDroppedUnrun() async throws {
    try await withWatchHost(model: .discarding()) { host, _, world in
      try Watching.raise("过时", deadline: Watching.minutes(5, after: world.now), on: host, world)
      world.advance(minutes: 6)
      await host.worker.consider()

      #expect(try host.database.openEvents().isEmpty)
      #expect(Background.prompts(world, starting: WatchCompanion.prefix).isEmpty)
    }
  }

  @Test func aHomesFindingsStartAtMostTheirBudgetAnHour() async throws {
    try await withWatchHost(model: .discarding()) { host, _, world in
      for index in 0...Worker.wakesPerHour {
        try Watching.raise("第 \(index) 条", deadline: Watching.minutes(600, after: world.now), on: host, world)
      }
      for _ in 0...Worker.wakesPerHour {
        await host.worker.consider()
        await host.worker.quiet(.chat)
      }
      #expect(Background.prompts(world, starting: WatchCompanion.prefix).count == Worker.wakesPerHour)
      #expect(try host.database.openEvents().count == 1)

      world.advance(minutes: 61)
      await host.worker.consider()
      await host.worker.quiet(.chat)
      #expect(Background.prompts(world, starting: WatchCompanion.prefix).count == Worker.wakesPerHour + 1)
    }
  }

  @Test func theSameFindingAgainIsRaisedOnce() async throws {
    try await withWatchHost(model: .discarding()) { host, _, world in
      let deadline = Watching.minutes(60, after: world.now)
      try Watching.raise("国常会稳市", deadline: deadline, on: host, world)
      try Watching.raise("国常会稳市", deadline: deadline, on: host, world)
      #expect(try Watching.findings(host).count == 1)
    }
  }
}
