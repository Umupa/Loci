import AppKit
import LociModel
import Synchronization
import Testing

@testable import LociUI

/// UI-S22: restarting into an update quits Loci. The updater quits from inside a main-actor job, and AppKit
/// then waits in a modal loop for the delegate to reply once the update is in place; a modal loop inside a
/// main-actor job runs no other main-actor work, so the reply must not need any.
@MainActor
@Suite(.onStage)
struct AppQuitTests {
  @Test func theDelegateRepliesWhileQuittingWaitsInsideAMainActorJob() {
    let delegate = LociAppDelegate()
    let updates = QuittingUpdates()
    delegate.updates = updates
    let replied = Replied()
    delegate.finishUpdate { replied.mark() }
    let deadline = Date.now.addingTimeInterval(5)
    while !replied.done, Date.now < deadline {
      RunLoop.current.run(mode: .modalPanel, before: Date.now.addingTimeInterval(0.02))
    }
    #expect(updates.finished.withLock { $0 })
    #expect(replied.done)
  }
}

private final class Replied: Sendable {
  private let sent = Mutex(false)
  var done: Bool { sent.withLock { $0 } }
  func mark() { sent.withLock { $0 = true } }
}

private final class QuittingUpdates: Updates {
  let finished = Mutex(false)

  func check() async throws(UpdateCheckError) {}

  func states() -> AsyncStream<AppUpdate> { AsyncStream { $0.yield(.current) } }

  func retry() async {}

  func restart() async {}

  func finishOnQuit() async {
    finished.withLock { $0 = true }
  }
}
