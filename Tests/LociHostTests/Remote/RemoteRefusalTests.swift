import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociHost

/// NX-S9, PJ-S2: a subscription an older Mac does not know is refused once on a connection and not asked
/// again until the next one.
@Suite(.timeLimit(.minutes(1)))
struct RemoteRefusalTests {
  /// What a newer Mac might follow that this one has never heard of.
  struct FutureWatch: Subscription {
    static let name = "future.watch"

    func value(from handler: any CommandHandler) async throws(HostError) -> Done { Done() }
    func isAffected(by changes: Set<ContentChange>) -> Bool { false }
  }

  @Test func aSubscriptionTheOtherMacRefusesIsNotAskedAgainOnTheSameConnection() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let remote = macs.laptop.service.open(macs.studio.machine.id)
      let refusals = Mutex(0)

      let watching = Task {
        for await feed in remote.subscribe(FutureWatch()) {
          if case .unavailable = feed { refusals.withLock { $0 += 1 } }
        }
      }
      for _ in 0..<200 where refusals.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(10)) }
      try await Task.sleep(for: .milliseconds(500))
      watching.cancel()

      #expect(refusals.withLock { $0 } == 1)
    }
  }

  @Test func closingAPageAfterARefusalLeavesNothingWaitingOnTheConnection() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let studio = macs.studio.machine.id
      let remote = macs.laptop.service.open(studio)
      let session = try #require(await macs.laptop.service.link(to: studio)?.currentControl)
      let before = await session.waitingForEnd

      for _ in 0..<3 {
        let refused = Mutex(false)
        let watching = Task {
          for await feed in remote.subscribe(FutureWatch()) {
            if case .unavailable = feed { refused.withLock { $0 = true } }
          }
        }
        for _ in 0..<200 where !refused.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
        for _ in 0..<200 where await session.waitingForEnd == before { try await Task.sleep(for: .milliseconds(5)) }
        watching.cancel()
        _ = await watching.value
      }
      for _ in 0..<200 where await session.waitingForEnd > before { try await Task.sleep(for: .milliseconds(5)) }
      let waiting = await session.waitingForEnd

      #expect(waiting == before)
      #expect(await macs.laptop.service.link(to: studio)?.currentControl != nil)
    }
  }
}
