import LociModel

/// What a run's session may touch, as the worker gives it in one read.
struct RunAccess: Equatable, Sendable {
  let policy: RunPolicy
  let home: Home
  let repair: RepairGrant?
}

/// What a repair may save: the one source it mends, as it was when the repair started. It is opened as the
/// run starts and closed as it ends, in `SourceCommits`, and a save under it is kept only while it is open
/// and that definition is still the saved one and still broken.
struct RepairGrant: Hashable, Sendable {
  let run: Run.ID
  let source: SourceKey
  let broken: DataSource

  static let over = "This repair is over; nothing was saved."
}

/// What a run's session may do with `loci`.
enum RunPolicy: Equatable, Sendable {
  /// Only panels' refreshes: read, save those panels, and put cards on the deck.
  case panel
  /// Schedules and follow-ups: read, set follow-ups, save the panels they keep, and put cards on the deck.
  case timers
  /// The daily review: read, set follow-ups, and say how it feels.
  case review
  /// Mending a source: show, test and save that source only.
  case repair

  func refusal(_ name: String) -> String {
    switch self {
    case .panel:
      "A panel's refresh only reads, saves its own panel and puts cards on the deck; loci cannot run \(name) in it."
    case .timers:
      "A run in the background only reads, sets follow-ups, saves its own panel and puts cards on the deck; loci "
        + "cannot run \(name) in it."
    case .review: "The daily review only reads, sets follow-ups and sets your mood; loci cannot run \(name) in it."
    case .repair: "Mending a source only shows, tests and saves that source; loci cannot run \(name) in it."
    }
  }
}

/// Whether a run may save a panel.
enum PanelPermission: Equatable {
  case allowed
  /// The run is over, or what it was for was removed.
  case stopped
  /// It may save only these.
  case only([String])
  /// It may save none.
  case none
}
