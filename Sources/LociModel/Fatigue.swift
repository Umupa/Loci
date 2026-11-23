import Foundation

/// How tired the companion is, from 0 to 100: each message adds to it, quiet time takes from it, and the
/// night pulls it up. Sleeping and waking are the companion's own choice, with one exception: asleep for
/// more than two hours in the day, it wakes up by itself.
public struct Fatigue: Hashable, Codable, Sendable {
  /// What the messages left, before the quiet since the last one and the hour are counted.
  public private(set) var amount: Double
  public private(set) var lastHeard: Timestamp?
  public private(set) var rest: Rest

  public enum Rest: Hashable, Codable, Sendable {
    case awake
    case asleep(since: Timestamp)
    /// Woken by hand, which keeps it awake for two hours whatever the amount says, except deep in the night.
    case woken(at: Timestamp)
  }

  public init(amount: Double = 0, lastHeard: Timestamp? = nil, rest: Rest = .awake) {
    self.amount = min(max(amount, 0), 100)
    self.lastHeard = lastHeard
    self.rest = rest
  }

  static let perMessage = 1.5
  static let recoveredPerMinute = 0.8
  static let wokenFor: Int64 = 2 * 3_600_000
  static let sleepsAtLeast: Int64 = 2 * 3_600_000
  static let wakingRelief = 30.0
  static let sleepingRelief = 40.0

  /// What the hour adds: most from 1:00 to 6:00, less in the rest of the night, a little after lunch.
  static func pull(at hour: Int) -> Double {
    switch hour {
    case 1..<6: 30
    case 23..., 0, 6..<8: 15
    case 13...14: 8
    default: 0
    }
  }

  /// How tired it is at `now`, 0 to 100, and what that makes it.
  public func felt(at now: Timestamp, in timeZone: TimeZone) -> (amount: Int, tiredness: Tiredness) {
    let hour = TimeOfDay(of: now, in: timeZone).hour
    let current = Int(min(100, recovered(at: now) + Self.pull(at: hour)).rounded(.toNearestOrAwayFromZero))
    let tiredness: Tiredness
    switch rest {
    case .asleep: tiredness = .asleep
    case .woken where !(1..<6).contains(hour): tiredness = .awake
    case .awake, .woken: tiredness = Tiredness(current)
    }
    return (current, tiredness)
  }

  /// Wakes up by itself when it has slept more than two hours and it is between 8:00 and 22:00.
  public mutating func wakeIfRested(at now: Timestamp, in timeZone: TimeZone) {
    guard case .asleep(let since) = rest, (8..<22).contains(TimeOfDay(of: now, in: timeZone).hour),
      now.millisecondsSince1970 - since.millisecondsSince1970 > Self.sleepsAtLeast
    else { return }
    rest = .awake
    amount = max(0, amount - Self.sleepingRelief)
  }

  /// A message came in.
  public mutating func heard(at now: Timestamp, in timeZone: TimeZone) {
    wakeIfRested(at: now, in: timeZone)
    amount = min(100, recovered(at: now) + Self.perMessage)
    lastHeard = now
    if case .woken(let at) = rest, now.millisecondsSince1970 - at.millisecondsSince1970 > Self.wokenFor {
      rest = .awake
    }
  }

  public mutating func sleep(at now: Timestamp) {
    rest = .asleep(since: now)
  }

  public mutating func wake(at now: Timestamp) {
    rest = .woken(at: now)
    amount = max(0, amount - Self.wakingRelief)
  }

  private func recovered(at now: Timestamp) -> Double {
    guard let lastHeard else { return amount }
    let minutes = Double(max(now.millisecondsSince1970 - lastHeard.millisecondsSince1970, 0)) / 60_000
    return max(0, amount - minutes * Self.recoveredPerMinute)
  }
}

/// How tiredness shows: awake below 30, tired from 30, sleepy from 50, asleep from 75 or when it went to sleep.
public enum Tiredness: String, Hashable, Codable, Sendable, CaseIterable {
  case awake, tired, sleepy, asleep

  init(_ amount: Int) {
    switch amount {
    case 75...: self = .asleep
    case 50...: self = .sleepy
    case 30...: self = .tired
    default: self = .awake
    }
  }
}

/// What the companion feels and how tired it is, kept in `agent/feelings.json`.
public struct Feelings: Hashable, Codable, Sendable {
  public var moods: Moods
  public var fatigue: Fatigue

  public init(moods: Moods = Moods(), fatigue: Fatigue = Fatigue()) {
    self.moods = moods
    self.fatigue = fatigue
  }
}
