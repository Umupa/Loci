import Foundation
import LociModel
import Testing

@testable import LociHost

/// A Mac on the same network cannot flood another with pairing requests.
@Suite(.timeLimit(.minutes(1)))
struct PairingLimitTests {
  static func studio(seenBy mac: TwoMacs.OneMac) async throws -> NearbyMac {
    try #require(
      await firstOf(mac.service.nearby()) { $0.contains { $0.name == "Mac Studio" } }?.first { $0.name == "Mac Studio" }
    )
  }

  static func requests(_ macs: TwoMacs, count: Int) async -> Bool {
    await firstOf(macs.studio.service.requests()) { $0.count == count } != nil
  }

  @Test func aMacHasOnlyOneRequestShownAtATime() async throws {
    try await TwoMacs.with { macs in
      let studio = try await Self.studio(seenBy: macs.laptop)
      var first = macs.laptop.service.pair(with: studio).makeAsyncIterator()
      guard case .code = await first.next() else { throw Unexpected() }
      #expect(await Self.requests(macs, count: 1))

      var second = macs.laptop.service.pair(with: studio).makeAsyncIterator()

      guard case .failed = await second.next() else { throw Unexpected() }
      #expect(await Self.requests(macs, count: 1))
      withExtendedLifetime(first) {}
    }
  }

  @Test func atMostThreeRequestsAreShownAtOnce() async throws {
    try await TwoMacs.with { macs in
      var askers = [macs.laptop]
      for index in 1...3 {
        askers.append(
          try await TwoMacs.mac(
            "Mac \(index)", model: .mini, relay: macs.relay, network: macs.network, agent: FakeAgent(),
            setting: macs.setting))
      }
      var waiting: [AsyncStream<PairingStep>.Iterator] = []
      for asker in askers.prefix(3) {
        var steps = asker.service.pair(with: try await Self.studio(seenBy: asker)).makeAsyncIterator()
        guard case .code = await steps.next() else { throw Unexpected() }
        waiting.append(steps)
      }
      #expect(await Self.requests(macs, count: 3))

      var fourth = askers[3].service.pair(with: try await Self.studio(seenBy: askers[3])).makeAsyncIterator()

      guard case .failed = await fourth.next() else { throw Unexpected() }
      #expect(await Self.requests(macs, count: 3))
      for asker in askers.dropFirst() {
        await asker.service.stop()
        await asker.local.close()
        asker.place.remove()
      }
      withExtendedLifetime(waiting) {}
    }
  }

  @Test func aDeclinedMacIsNotHeardForThirtySeconds() async throws {
    try await TwoMacs.with { macs in
      let studio = try await Self.studio(seenBy: macs.laptop)
      var asking = macs.laptop.service.pair(with: studio).makeAsyncIterator()
      guard case .code = await asking.next() else { throw Unexpected() }
      let request = try #require(await firstOf(macs.studio.service.requests()) { !$0.isEmpty }?.first)
      await macs.studio.service.answer(request.id, allow: false)
      guard case .failed(.declined) = await asking.next() else { throw Unexpected() }

      macs.setting.time.advance(seconds: 29)
      var again = macs.laptop.service.pair(with: studio).makeAsyncIterator()
      guard case .failed = await again.next() else { throw Unexpected() }
      #expect(await Self.requests(macs, count: 0))

      macs.setting.time.advance(seconds: 1)
      var later = macs.laptop.service.pair(with: studio).makeAsyncIterator()
      guard case .code = await later.next() else { throw Unexpected() }
      #expect(await Self.requests(macs, count: 1))
    }
  }
}
