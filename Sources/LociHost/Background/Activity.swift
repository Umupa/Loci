import Foundation

/// Work the app declared to macOS, which ends when `end` is called.
public struct Activity: Sendable {
  public let end: @Sendable () -> Void

  public init(end: @escaping @Sendable () -> Void) {
    self.end = end
  }
}

/// A `ProcessInfo` activity that keeps App Nap from putting off a run while no window is open. It lets the
/// Mac sleep when idle: a run on a sleeping Mac is made up when it wakes.
actor ProcessActivity {
  private var token: (any NSObjectProtocol)?
  /// Ending may reach the actor before starting does; then it never starts.
  private var ended = false

  static func begin(_ reason: String) -> Activity {
    let activity = ProcessActivity()
    Task { await activity.start(reason) }
    return Activity { Task { await activity.stop() } }
  }

  private func start(_ reason: String) {
    guard token == nil, !ended else { return }
    token = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: reason)
  }

  private func stop() {
    ended = true
    if let token { ProcessInfo.processInfo.endActivity(token) }
    token = nil
  }
}
