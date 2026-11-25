import Foundation
import LociModel
import Testing

@testable import LociHost

/// NX-S9: the studio's deck is seen and dealt with from the laptop.
@Suite(.timeLimit(.minutes(1)))
struct RemoteNextUpTests {
  @Test func theLaptopSeesTheStudiosDeckAndDealsWithItsCards() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let studio = macs.studio.local
      let kept = try await studio.addNextUp(AddNextUp("纳指回撤到二十日线", asking: "还定投吗"))
      let declined = try await studio.addNextUp(AddNextUp("新的 ETF 上市", asking: "要看看吗"))

      let deck = try #require(await value(remote.subscribe(WatchNextUps(of: .chat))) { $0.count == 2 })
      _ = try await remote.run(SetNextUp(kept.id, .keep))
      _ = try await remote.run(SetNextUp(declined.id, .decline))

      #expect(Set(deck.map(\.id)) == [kept.id, declined.id])
      #expect(try await studio.nextUps(of: .chat).map(\.id) == [kept.id])
      #expect(try await studio.nextUps(of: .chat).first?.state == .kept)
      #expect(try await macs.laptop.local.nextUps(of: .chat).isEmpty)
    }
  }
}
