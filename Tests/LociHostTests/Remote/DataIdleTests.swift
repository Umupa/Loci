import Foundation
import LociModel
import Testing

@testable import LociHost

/// The data connection closes once it has been idle for a while, and is dialed again when needed.
@Suite(.timeLimit(.minutes(1)))
struct DataIdleTests {
  static func readImage(_ host: any LociModel.Host, _ mentor: EntityID) async {
    _ = try? await host.run(ReadItemImage(item: mentor, name: "missing.png"))
  }

  @Test func theDataConnectionClosesAfterAMinuteWithoutUse() async throws {
    let clock = ManualClock()
    try await TwoMacs.with(setting: TwoMacs.Setting(clock: clock, dataIdle: .seconds(60))) { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let mentor = try await remote.run(CreateMentor(request: "Scheduling"))
      let token = macs.studio.key.routeToken
      await Self.readImage(remote, mentor.id)
      #expect(await macs.relay.clientDials(to: token) == 3)

      await clock.sleeperArrives(sleepingAtLeast: .seconds(60))
      clock.advance(by: .seconds(59))
      await Self.readImage(remote, mentor.id)
      #expect(await macs.relay.clientDials(to: token) == 3)

      await clock.sleeperArrives(sleepingAtLeast: .seconds(60))
      clock.advance(by: .seconds(60))
      #expect(await macs.connected(macs.laptop, to: macs.studio))
      await Self.readImage(remote, mentor.id)

      #expect(await macs.relay.clientDials(to: token) == 4)
    }
  }

  @Test func aConnectionStillCarryingASubscriptionIsNotIdle() async throws {
    let clock = ManualClock()
    try await TwoMacs.with(setting: TwoMacs.Setting(clock: clock, dataIdle: .seconds(60))) { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let mentor = try await remote.run(CreateMentor(request: "Scheduling"))
      let token = macs.studio.key.routeToken
      let link = try #require(await macs.laptop.service.link(to: macs.studio.machine.id))
      let data = try #require(await link.session(for: .data))
      let (_, frames) = await data.subscribe(AllMentors.name, body: Data("{}".utf8))
      var updates = frames.makeAsyncIterator()
      _ = await updates.next()

      await clock.sleeperArrives(sleepingAtLeast: .seconds(60))
      clock.advance(by: .seconds(61))
      await clock.sleeperArrives(sleepingAtLeast: .seconds(60))
      await Self.readImage(remote, mentor.id)

      #expect(await macs.relay.clientDials(to: token) == 3)
    }
  }
}
