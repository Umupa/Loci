import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociHost

struct HostBusyTests {
  private static func job(_ stage: Job.Stage, _ state: Job.State) -> Job {
    Job(item: EntityID(), stage: stage, state: state)
  }

  @Test func answeringRunsAndLibraryWorkHoldARestart() {
    #expect(HostBusy.busy(work: .answering(nil), jobs: []) == .answering)
    #expect(HostBusy.busy(work: .refreshing(title: "Inbox"), jobs: []) == .running)
    #expect(HostBusy.busy(work: .reviewing, jobs: []) == .running)
    #expect(HostBusy.busy(work: .looking(title: "Morning"), jobs: []) == .running)
    #expect(HostBusy.busy(work: .saving, jobs: []) == .library)
    for stage in [Job.Stage.download, .transcribe, .diarize] {
      #expect(HostBusy.busy(work: nil, jobs: [Self.job(stage, .running(progress: nil))]) == .library)
    }
  }

  @Test func answeringIsNamedBeforeTheLibrary() {
    let jobs = [Self.job(.transcribe, .running(progress: nil))]
    #expect(HostBusy.busy(work: .answering(nil), jobs: jobs) == .answering)
  }

  @Test func queuedPausedOrLightJobsDoNotHoldARestart() {
    let jobs = [
      Self.job(.transcribe, .queued), Self.job(.download, .paused(progress: nil)),
      Self.job(.outline, .running(progress: nil)), Self.job(.translate, .running(progress: nil)),
    ]
    #expect(HostBusy.busy(work: nil, jobs: jobs) == nil)
  }

  @Test func busynessFollowsTheNewHostAfterTheOldOneEnds() async {
    let subscribed = Shared(0)
    let busy = HostBusy.of(
      status: {
        subscribed.change { $0 += 1 }
        return subscribed.value == 1
          ? AsyncStream {
            $0.yield(.answering(nil))
            $0.finish()
          }
          : AsyncStream { $0.yield(.reviewing) }
      },
      jobs: { AsyncStream { _ in } })
    var heard: [Busy?] = []
    for await now in busy {
      heard.append(now)
      if now == .running { break }
    }
    #expect(heard.first == .answering)
    #expect(heard.last == .running)
    #expect(subscribed.value == 2)
  }

  @Test func aSubscriptionThatEndsWithoutDeliveringIsNotMadeAgain() async {
    let subscribed = Shared(0)
    let busy = HostBusy.of(
      status: {
        subscribed.change { $0 += 1 }
        return AsyncStream { $0.finish() }
      },
      jobs: { AsyncStream { $0.yield([Self.job(.download, .running(progress: nil))]) } })
    for await now in busy where now == .library { break }
    for _ in 0..<100 { await Task.yield() }
    #expect(subscribed.value == 1)
  }

  @Test func closingTheHostEndsItsSubscriptions() async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld(agent: FakeAgent())
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: world.environment)
    var feed = host.subscribe(LociWorking()).makeAsyncIterator()
    _ = await feed.next()
    await host.close()
    #expect(await feed.next() == nil)
  }
}
