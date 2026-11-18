/// How long to wait before dialing again: doubling from `first` up to `longest`, each wait shortened by
/// up to a fifth at random so that many Macs coming back at once do not dial in step.
public struct Backoff: Sendable {
  public let first: Duration
  public let longest: Duration

  public init(first: Duration = .seconds(1), longest: Duration = .seconds(30)) {
    self.first = first
    self.longest = longest
  }

  /// `attempt` counts from 0; `random` is in `0..<1`.
  public func delay(attempt: Int, random: Double) -> Duration {
    let doubled = first * Int(1 << min(attempt, 20))
    let capped = min(doubled, longest)
    return capped - capped * (0.2 * min(max(random, 0), 1))
  }
}
