import Foundation
import LociModel
import LociRemote
import Testing

@testable import LociHost

/// Accepting an invite can be cancelled, and nothing is left half paired.
@Suite(.timeLimit(.minutes(1)))
struct InviteCancellationTests {
  @Test func aCancelledAcceptPairsNeitherMacAndTheInviteStillWorks() async throws {
    try await TwoMacs.with { macs in
      let invite = try await macs.studio.service.invite()
      await macs.relay.fallSilent()
      let accepting = Task { try await macs.laptop.service.accept(invite) }
      try await Task.sleep(for: .milliseconds(50))

      accepting.cancel()

      await #expect(throws: PairingFailure.cancelled) { _ = try await accepting.value }
      #expect(await macs.roster(of: macs.laptop) { $0.paired.isEmpty } != nil)
      #expect(await macs.roster(of: macs.studio) { $0.paired.isEmpty } != nil)
      await macs.relay.restart()
      await macs.relay.registration(of: macs.studio.key.routeToken)
      #expect(try await macs.laptop.service.accept(invite) == macs.studio.machine)
    }
  }

  @Test func anAcceptCancelledBeforeItStartsDialsNothing() async throws {
    try await TwoMacs.with { macs in
      let invite = try await macs.studio.service.invite()
      let accepting = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await macs.laptop.service.accept(invite)
      }

      await #expect(throws: PairingFailure.cancelled) { _ = try await accepting.value }
      #expect(await macs.relay.clientDials(to: macs.studio.key.routeToken) == 0)
    }
  }

  /// The other side of a cancelled accept: a Mac that finished the handshake but never confirmed is not
  /// added, and the invite can be used again.
  @Test func aHandshakeWithoutConfirmationAddsNoMac() async throws {
    try await TwoMacs.with { macs in
      let invite = try await macs.studio.service.invite()
      let quitter = try DeviceKey()
      let socket = try await RelayClient.open(
        macs.relay.relay, token: invite.address.routeToken, dialer: macs.relay, heartbeat: TwoMacs.quick)
      let greeted = try await Greeting.dial(
        socket, as: quitter, me: Machine(id: quitter.machineID, name: "Quitter", model: .other),
        to: invite.address, purpose: .invite(invite.id), preSharedKey: invite.secret)

      #expect(await macs.studio.service.redeemed[invite.id] != nil)
      await greeted.channel.close()
      #expect(await until { await macs.studio.service.redeemed[invite.id] == nil })

      #expect(try await macs.laptop.service.accept(invite) == macs.studio.machine)
      let roster = try #require(await macs.roster(of: macs.studio) { !$0.paired.isEmpty })
      #expect(roster.paired.map(\.machine) == [macs.laptop.machine])
    }
  }
}

/// Whether `condition` came true within `timeout`, checked every few milliseconds.
func until(within timeout: Duration = .seconds(5), _ condition: @Sendable () async -> Bool) async -> Bool {
  let deadline = ContinuousClock.now + timeout
  while ContinuousClock.now < deadline {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return false
}
