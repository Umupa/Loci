import AppKit
import Synchronization

/// A wait that ran out before what it waited for happened, and how often it looked: a wait the main thread starved
/// looked a few times, one for something that never came looked hundreds of times.
struct TimedOut: Error, CustomStringConvertible {
  let waitingFor: String
  let seen: String
  var description: String { "timed out waiting for \(waitingFor) (\(seen))" }
}

/// Waits until `condition` holds, checking it on the main actor every 20 ms, so a test does not depend on how
/// busy the machine is. Throws `TimedOut` if it still does not hold after `timeout`.
@MainActor
func eventually(
  _ waitingFor: String, within timeout: Duration = .seconds(30), _ condition: @MainActor () -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  var checks = 1
  while !condition() {
    guard ContinuousClock.now < deadline else {
      throw TimedOut(waitingFor: waitingFor, seen: "checked \(checks) times")
    }
    checks += 1
    try await Task.sleep(for: .milliseconds(20))
  }
}

/// Requests a fake host has been asked and not yet answered, so a test can wait for the data a view asked for.
final class Activity: Sendable {
  private let counts = Mutex((begun: 0, open: 0))

  func begin() {
    counts.withLock {
      $0.begun += 1
      $0.open += 1
    }
  }

  func end() {
    counts.withLock { $0.open -= 1 }
  }

  /// How many requests have been asked, and how many of them are not answered yet.
  var now: (begun: Int, open: Int) {
    counts.withLock { $0 }
  }
}

/// Holds once something was asked, everything asked has been answered, and nothing new has been asked for three
/// checks in a row. An answer reaches the view, and the view asks for what follows from it, between checks; a
/// view reading items one by one has nothing open for a moment between them, but keeps asking.
@MainActor
final class Quiet {
  private let activity: Activity
  private var last = -1
  private var streak = 0

  init(_ activity: Activity) {
    self.activity = activity
  }

  func settled() -> Bool {
    let now = activity.now
    streak = now.begun > 0 && now.open == 0 && now.begun == last ? streak + 1 : 0
    last = now.begun
    return streak >= 3
  }
}
