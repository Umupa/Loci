import LociModel
import SwiftUI

/// The work of making an item readable, as the steps of a task card. Reading what a link is and taking the
/// text out of a page are one step to the person: fetching.
enum JobSteps {
  enum Step: Equatable {
    case fetch, download, recognize, translate, outline

    init(_ stage: Job.Stage) {
      switch stage {
      case .resolve, .extract: self = .fetch
      case .download: self = .download
      case .transcribe: self = .recognize
      case .translate: self = .translate
      case .outline: self = .outline
      }
    }

    var name: LocalizedStringResource {
      switch self {
      case .fetch: .loci("job.fetching")
      case .download: .loci("job.downloading")
      case .recognize: .loci("job.recognizing")
      case .translate: .loci("job.translating")
      case .outline: .loci("job.outlining")
      }
    }
  }

  /// The steps an item of this kind goes through, in order.
  static func steps(for kind: Item.Kind) -> [Step] {
    switch kind {
    case .article, .paper, .repository: [.fetch]
    case .video, .audio: [.fetch, .download, .recognize, .translate, .outline]
    }
  }

  /// How far along the whole job is, from 0 to 1.
  static func progress(of job: Job, kind: Item.Kind) -> Double {
    let steps = steps(for: kind)
    guard let index = steps.firstIndex(of: Step(job.stage)) else { return 0 }
    let within: Double =
      switch job.state {
      case .done: 1
      case .running(let progress?, _): progress.value
      default: 0
      }
    return (Double(index) + within) / Double(steps.count)
  }

  /// Each step done, going on now, or still to come.
  static func states(of job: Job, kind: Item.Kind) -> [(step: Step, state: TaskCard.StepState)] {
    let steps = steps(for: kind)
    let current = steps.firstIndex(of: Step(job.stage)) ?? 0
    return steps.enumerated().map { index, step in
      if index < current || index == current && job.state == .done { return (step, .done) }
      return (step, index == current ? .now : .later)
    }
  }
}
