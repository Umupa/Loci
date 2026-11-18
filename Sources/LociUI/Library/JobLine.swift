import LociModel

/// What an item's row in the library says about the work on it: how far along, what it waits for, or why it
/// stopped and what fixes it. Finished work says nothing.
enum JobLine: Equatable {
  /// `nil` progress is work whose length cannot be told.
  case working(Activity, Fraction?)
  /// A button that gets the work going again.
  case action(Fix, reason: String?)
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
    case retry
    /// Stopped by the reader; carries on from what was made.
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
    case .running(let progress):
      self = .working(Self.activity(job.stage), progress)
    case .waiting(let need):
      switch need {
      case .component(let component): self = .action(.downloadComponent(component), reason: nil)
      case .speechModel(let model): self = .action(.downloadModel(model), reason: nil)
      case .login(let site): self = .action(.signIn(site: site), reason: nil)
      case .agent: self = .action(.chooseAgent, reason: nil)
      }
    case .failed(let failure):
      let fix: Fix =
        switch failure.remedy {
        case .updateComponent(let component): .update(component)
        case .chooseBrowserLogin: .chooseBrowserLogin
        case .retry, nil: .retry
        }
      self = .action(fix, reason: failure.reason)
    case .stopped:
      self = .action(.resume, reason: nil)
    }
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
