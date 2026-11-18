import Foundation
import LociModel
import LociRemote
import Testing

@testable import LociHost

/// R-S2, R-S3, R-S8: pairing nearby and by invite, and removing a Mac.
@Suite(.timeLimit(.minutes(1)))
struct PairingScenarioTests {
  /// R-S2: the laptop finds the studio nearby, both show the same code, the studio allows, and both
  /// rosters gain the other.
  @Test func twoMacsPairNearbyOnceTheCodeIsAllowed() async throws {
    try await TwoMacs.with { macs in
      let found = await firstOf(macs.laptop.service.nearby()) { $0.contains { $0.name == "Mac Studio" } }
      let studio = try #require(found?.first { $0.name == "Mac Studio" })
      #expect(found?.contains { $0.id == macs.laptop.machine.id } == false)
      var steps = macs.laptop.service.pair(with: studio).makeAsyncIterator()

      guard case .code(let shown) = await steps.next() else { throw Unexpected() }
      let request = try #require(await firstOf(macs.studio.service.requests()) { !$0.isEmpty }?.first)
      #expect(request.code == shown)
      #expect(request.from == macs.laptop.machine)
      await macs.studio.service.answer(request.id, allow: true)

      guard case .paired(let paired) = await steps.next() else { throw Unexpected() }
      #expect(paired == macs.studio.machine)
      #expect(await macs.connected(macs.laptop, to: macs.studio))
      #expect(await macs.connected(macs.studio, to: macs.laptop))
      #expect(await firstOf(macs.studio.service.requests()) { $0.isEmpty } != nil)
    }
  }

  @Test func aDeclinedPairingLeavesBothRostersAsTheyWere() async throws {
    try await TwoMacs.with { macs in
      let studio = try #require(await firstOf(macs.laptop.service.nearby()) { !$0.isEmpty }?.first)
      var steps = macs.laptop.service.pair(with: studio).makeAsyncIterator()
      guard case .code = await steps.next() else { throw Unexpected() }
      let request = try #require(await firstOf(macs.studio.service.requests()) { !$0.isEmpty }?.first)

      await macs.studio.service.answer(request.id, allow: false)

      guard case .failed(let failure) = await steps.next() else { throw Unexpected() }
      #expect(failure == .declined)
      #expect(await macs.roster(of: macs.studio) { $0.paired.isEmpty } != nil)
      #expect(await macs.roster(of: macs.laptop) { $0.paired.isEmpty } != nil)
    }
  }

  @Test func aRequestDisappearsWhenTheAskingMacGivesUp() async throws {
    try await TwoMacs.with { macs in
      let studio = try #require(await firstOf(macs.laptop.service.nearby()) { !$0.isEmpty }?.first)
      let asking = Task {
        for await step in macs.laptop.service.pair(with: studio) { _ = step }
      }
      #expect(await firstOf(macs.studio.service.requests()) { !$0.isEmpty } != nil)

      asking.cancel()

      #expect(await firstOf(macs.studio.service.requests()) { $0.isEmpty } != nil)
    }
  }

  /// R-S3: a pasted invite pairs both Macs; pasting it again says it was used.
  @Test func anInvitePairsBothMacsOnce() async throws {
    try await TwoMacs.with { macs in
      let invite = try await macs.studio.service.invite()
      let pasted = try #require(Invite(pasted: invite.link))

      let paired = try await macs.laptop.service.accept(pasted)

      #expect(paired == macs.studio.machine)
      #expect(await macs.connected(macs.laptop, to: macs.studio))
      #expect(await macs.connected(macs.studio, to: macs.laptop))
      await #expect(throws: PairingFailure.used) { _ = try await macs.laptop.service.accept(pasted) }
    }
  }

  @Test func anExpiredInviteIsRefusedBeforeDialing() async throws {
    try await TwoMacs.with { macs in
      let key = try DeviceKey()
      let stale = try #require(
        Invite(
          id: EntityID(), name: "Mac Studio", model: .studio, address: key.address, secret: Data(count: 32),
          expires: Timestamp(millisecondsSince1970: TestWorld.instant.millisecondsSince1970 - 1)))

      await #expect(throws: PairingFailure.expired) { _ = try await macs.laptop.service.accept(stale) }
    }
  }

  /// R-S8: removing a Mac disconnects it at once; it drops the Mac that removed it, and its host is offline.
  @Test func aRemovedMacIsDisconnectedAndRemovesTheOtherToo() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let studioHost = macs.laptop.service.open(macs.studio.machine.id)
      _ = try await studioHost.run(ListItems())

      await macs.studio.service.remove(macs.laptop.machine.id)

      #expect(await macs.roster(of: macs.studio) { $0.paired.isEmpty } != nil)
      #expect(await macs.roster(of: macs.laptop) { $0.paired.isEmpty } != nil)
      await #expect(throws: HostError.offline) { _ = try await studioHost.run(ListItems()) }
    }
  }

  /// A read whose reply arrives after its Mac was removed does not bring back what was kept of it.
  @Test func aReplyArrivingAfterRemovalIsNotKept() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let studio = macs.studio.machine.id
      await macs.laptop.service.remove(studio)

      await macs.laptop.service.keep(Data("[]".utf8), as: ListItems.name, request: Data("{}".utf8), on: studio)

      #expect(macs.laptop.machineFolder.cached(ListItems.name, request: Data("{}".utf8), on: studio) == nil)
      await #expect(throws: HostError.offline) {
        _ = try await macs.laptop.service.open(studio).run(ListItems())
      }
    }
  }

  @Test func aMacThatWasRemovedWhileAwayIsRefusedAndDropsTheOther() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      await macs.laptop.service.stop()
      await macs.studio.service.remove(macs.laptop.machine.id)

      let returning = try await TwoMacs.mac(
        "MacBook", model: .laptop, relay: macs.relay, network: FakeLocalNetwork(), agent: FakeAgent(),
        reusing: macs.laptop)
      defer { Task { await returning.service.stop() } }

      #expect(await macs.roster(of: returning) { $0.paired.isEmpty } != nil)
    }
  }

  /// The Mac stays awake while another Mac may want to open it, and not otherwise.
  @Test func theMacStaysAwakeOnlyWhileSomethingIsPaired() async throws {
    try await TwoMacs.with { macs in
      #expect(await macs.studio.awake.isKeptAwake == false)
      try await macs.pair()
      #expect(await macs.studio.awake.isKeptAwake)

      await macs.studio.service.remove(macs.laptop.machine.id)

      #expect(await macs.studio.awake.isKeptAwake == false)
    }
  }

  @Test func theRosterAlwaysStartsWithThisMac() async throws {
    try await TwoMacs.with { macs in
      let roster = try #require(await macs.roster(of: macs.laptop) { _ in true })

      #expect(roster.this == macs.laptop.machine)
      #expect(roster.paired.isEmpty)
      #expect(macs.laptop.service.open(macs.laptop.machine.id) is LocalHost)
    }
  }
}

struct Unexpected: Error {}
