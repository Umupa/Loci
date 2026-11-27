import Foundation
import LociModel
import Testing

@testable import LociHost

/// FO-S3, FO-S7: the studio's follows are seen, opened and stopped from the laptop.
@Suite(.timeLimit(.minutes(1)))
struct RemoteFollowTests {
  @Test func theLaptopSeesTheStudiosFollowsAndStopsOne() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let follow = Follow(
        id: EntityID(), source: .youtube(channel: "UCdwarkesh"), name: "Dwarkesh Patel",
        page: FollowSamples.channel, followed: TestWorld.instant)
      try macs.studio.place.store.changeFollows { $0.append(follow) }

      let row = try #require(await value(remote.subscribe(AllFollows())) { $0.count == 1 })
      #expect(row.first?.follow.name == "Dwarkesh Patel")
      #expect(try #require(await value(remote.subscribe(OneFollow(follow.id))) { $0 != nil })?.follow.id == follow.id)

      _ = try await remote.run(SawFollow(follow.id))
      let stopped = try await remote.run(StopFollowing(follow.id))

      #expect(stopped.id == follow.id)
      #expect(macs.studio.place.store.follows().isEmpty)
      #expect(macs.laptop.place.store.follows().isEmpty)
    }
  }
}
