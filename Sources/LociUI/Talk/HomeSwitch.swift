import LociModel
import SwiftUI
import os

/// Times each turn from one home to another until its page is filled: when the conversation arrives, when the
/// panels do, and when both are in. A page kept made while others show counts what it already has.
@MainActor
final class HomeSwitch {
  enum Part: Hashable {
    case conversation
    case panels
  }

  enum Event: Equatable {
    case began(Home)
    case arrived(Part, after: Duration)
    case settled(after: Duration)
    /// Another turn came before this one settled.
    case abandoned(after: Duration)
  }

  private struct Turn {
    let home: Home
    let start: ContinuousClock.Instant
    var arrived: Set<Part>
  }

  private let now: () -> ContinuousClock.Instant
  private let report: (Event) -> Void
  private var turn: Turn?
  /// What each home's page has had arrive since it was made.
  private var filled: [Home: Set<Part>] = [:]

  init(now: @escaping () -> ContinuousClock.Instant, report: @escaping (Event) -> Void) {
    self.now = now
    self.report = report
  }

  /// Reports each turn as an interval Instruments shows beside the frames, and as lines in the log.
  static func logged() -> HomeSwitch {
    let log = SwitchLog()
    return HomeSwitch(now: { ContinuousClock.now }, report: log.record)
  }

  /// The person chose `home`, before the page changes. `kept` is whether its page stayed made while others
  /// showed; otherwise it is made again and has nothing yet.
  func turned(to home: Home, kept: Bool) {
    left()
    if !kept { filled[home] = [] }
    let start = now()
    report(.began(home))
    turn = Turn(home: home, start: start, arrived: filled[home, default: []])
    settleIfFilled()
  }

  func arrived(_ part: Part, in home: Home) {
    filled[home, default: []].insert(part)
    guard var shown = turn, shown.home == home, shown.arrived.insert(part).inserted else { return }
    report(.arrived(part, after: now() - shown.start))
    turn = shown
    settleIfFilled()
  }

  /// The page now shows `home`; a turn to another one is over.
  func shown(_ home: Home) {
    if let turn, turn.home != home { left() }
  }

  /// The page the turn was to is no longer coming, such as when the companion's page goes away.
  func left() {
    guard let turn else { return }
    report(.abandoned(after: now() - turn.start))
    self.turn = nil
  }

  private func settleIfFilled() {
    guard let turn, turn.arrived.count == 2 else { return }
    report(.settled(after: now() - turn.start))
    self.turn = nil
  }
}

@MainActor
private final class SwitchLog {
  private static let subsystem = "com.loci.native.dev"
  private let signposter = OSSignposter(subsystem: subsystem, category: "switch")
  private let log = Logger(subsystem: subsystem, category: "switch")
  private var interval: (id: OSSignpostID, state: OSSignpostIntervalState)?
  private var home = "chat"

  func record(_ event: HomeSwitch.Event) {
    switch event {
    case .began(let turned):
      home = turned == .chat ? "chat" : "project"
      let id = signposter.makeSignpostID()
      interval = (id, signposter.beginInterval("turn", id: id, "\(self.home, privacy: .public)"))
    case .arrived(let part, let elapsed):
      let name = part == .conversation ? "conversation" : "panels"
      signposter.emitEvent("arrived", id: interval?.id ?? .exclusive, "\(name, privacy: .public)")
      log.notice("turn to \(self.home, privacy: .public): \(name, privacy: .public) in \(elapsed.milliseconds) ms")
    case .settled(let elapsed):
      end("settled")
      log.notice("turn to \(self.home, privacy: .public) settled in \(elapsed.milliseconds) ms")
    case .abandoned(let elapsed):
      end("abandoned")
      log.notice("turn to \(self.home, privacy: .public) abandoned after \(elapsed.milliseconds) ms")
    }
  }

  private func end(_ how: StaticString) {
    guard let interval else { return }
    signposter.endInterval("turn", interval.state, "\(how)")
    self.interval = nil
  }
}

extension Duration {
  fileprivate var milliseconds: Int {
    let (seconds, attoseconds) = components
    return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
  }
}

extension EnvironmentValues {
  /// Times the turn to the home being shown; `nil` outside the companion's page and for another Mac, whose
  /// timings would include the network.
  @Entry var homeSwitch: HomeSwitch?
}
