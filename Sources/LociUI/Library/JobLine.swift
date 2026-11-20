import LociModel

/// What an item's row in the library says about the work on it: how far along, what it waits for, or why it
/// stopped and what fixes it. Finished work says nothing.
enum JobLine: Equatable {
  /// `nil` progress is work whose length cannot be told.
  case working(Activity, Fraction?)
  /// A button that gets the work going again, and what went wrong when something did.
  case action(Fix, Problem?)
  case none

  enum Activity: Equatable {
    case fetching, downloading, recognizing, translating, outlining, queued
  }

  enum Fix: Equatable {
    case downloadComponent(Component)
    case downloadModel(SpeechModel)
    case signIn(site: String)
    case chooseAgent
    case update(Component)
    case chooseBrowserLogin
    /// Shows the original page, where the site says why it will not give the item.
    case openSource
    case retry
    /// Paused by the reader; carries on from what was made.
    case resume
  }

  init(_ job: Job?) {
    guard let job else {
      self = .none
      return
    }
    switch job.state {
    case .done:
      self = .none
    case .queued:
      self = .working(.queued, nil)
    case .running(let progress, _):
      self = .working(Self.activity(job.stage), progress)
    case .waiting(let need):
      switch need {
      case .component(let component): self = .action(.downloadComponent(component), nil)
      case .speechModel(let model): self = .action(.downloadModel(model), nil)
      case .login(let site): self = .action(.signIn(site: site), nil)
      case .agent: self = .action(.chooseAgent, nil)
      }
    case .failed(let failure):
      let fix: Fix =
        switch failure.remedy {
        case .updateComponent(let component): .update(component)
        case .chooseBrowserLogin: .chooseBrowserLogin
        case .openSource: .openSource
        case .retry, nil: .retry
        }
      self = .action(fix, Problem(stage: job.stage, cause: failure.cause, reason: failure.reason))
    case .paused:
      self = .action(.resume, nil)
    }
  }

  /// Why work failed: the kind of trouble, told in the reader's language, and the program's own words for
  /// those who want them.
  struct Problem: Equatable {
    let stage: Job.Stage
    let cause: Job.Cause?
    let reason: String
  }

  private static func activity(_ stage: Job.Stage) -> Activity {
    switch stage {
    case .resolve, .extract: .fetching
    case .download: .downloading
    case .transcribe: .recognizing
    case .translate: .translating
    case .outline: .outlining
    }
  }
}
