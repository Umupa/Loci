import Foundation
import LociModel
import Synchronization
import Testing

struct InviteFixtureTests {
  @Test func askingAgainAfterAnInviteExpiresReturnsAUsableLink() async throws {
    let issuedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let time = Mutex(issuedAt)
    let machines = FakeMachines(hosts: [:], now: { time.withLock { $0 } })

    let first = try await machines.invite()
    #expect(!first.hasExpired(at: Timestamp(issuedAt)))

    let later = issuedAt.addingTimeInterval(601)
    time.withLock { $0 = later }
    #expect(first.hasExpired(at: Timestamp(later)))

    let renewed = try await machines.invite()
    #expect(renewed.id != first.id)
    #expect(!renewed.hasExpired(at: Timestamp(later)))
  }
}
