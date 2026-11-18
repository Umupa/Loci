import Synchronization

/// A clock that moves only when told. Sleepers wake when `advance` passes their deadline.
final class ManualClock: Clock, Sendable {
  struct Instant: InstantProtocol {
    let offset: Duration

    func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
    func duration(to other: Instant) -> Duration { other.offset - offset }
    static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Sleeper {
    let deadline: Instant
    let wake: CheckedContinuation<Void, any Error>
  }

  private struct State {
    var now = Instant(offset: .zero)
    var sleepers: [Int: Sleeper] = [:]
    var next = 0
  }

  private let state = Mutex(State())

  var now: Instant { state.withLock { $0.now } }
  var minimumResolution: Duration { .zero }

  func sleep(until deadline: Instant, tolerance: Duration?) async throws {
    let id = state.withLock { state in
      state.next += 1
      return state.next
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (wake: CheckedContinuation<Void, any Error>) in
        let due = state.withLock { state in
          guard deadline > state.now, !Task.isCancelled else { return true }
          state.sleepers[id] = Sleeper(deadline: deadline, wake: wake)
          return false
        }
        if due {
          if Task.isCancelled { wake.resume(throwing: CancellationError()) } else { wake.resume() }
        }
      }
    } onCancel: {
      state.withLock { $0.sleepers.removeValue(forKey: id) }?.wake.resume(throwing: CancellationError())
    }
  }

  /// Moves time forward and wakes everyone whose deadline has come.
  func advance(by duration: Duration) {
    let woken = state.withLock { state in
      state.now = state.now.advanced(by: duration)
      let now = state.now
      let due = state.sleepers.filter { $0.value.deadline <= now }
      for id in due.keys { state.sleepers[id] = nil }
      return due.values.map(\.wake)
    }
    for wake in woken { wake.resume() }
  }

  /// Returns once someone sleeps until at least `duration` from now.
  func sleeperArrives(sleepingAtLeast duration: Duration) async {
    while !state.withLock({ state in state.sleepers.values.contains { state.now.duration(to: $0.deadline) >= duration }
    }) {
      await Task.yield()
    }
  }
}
