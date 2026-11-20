import LociModel

/// How an item's card in the gallery looks for the work on it.
enum CardState: Equatable {
  /// Nothing going on: the plain cover.
  case ready
  /// Waiting its turn before anything was made.
  case queued
  /// A stage under way, with its share when it can be told.
  case working(Job.Stage, Fraction?)
  /// With how far its stage had got.
  case paused(Fraction?)
  /// Waiting for the reader, or failed: the button that gets it going again sits in the middle of the cover.
  case needs(JobLine.Fix)

  init(_ job: Job?) {
    guard let job else {
      self = .ready
      return
    }
    switch job.state {
    case .done: self = .ready
    case .paused(let progress): self = .paused(progress)
    case .queued: self = job.stage == (job.stages.first ?? job.stage) ? .queued : .working(job.stage, nil)
    case .running(let progress, _): self = .working(job.stage, progress)
    case .waiting, .failed:
      if case .action(let fix, _) = JobLine(job) { self = .needs(fix) } else { self = .ready }
    }
  }

  /// Whether work is going on or wanted: the cover is blurred and the ruler shows.
  var isBusy: Bool { self != .ready }

  var isPaused: Bool {
    if case .paused = self { return true }
    return false
  }

  /// Whether the amber light runs around the cover.
  var glows: Bool {
    if case .working = self { return true }
    return false
  }

  /// Whether the card offers to pause or carry on, and to cancel, when pointed at.
  var pausable: Bool {
    switch self {
    case .queued, .working, .paused: true
    case .ready, .needs: false
    }
  }
}
