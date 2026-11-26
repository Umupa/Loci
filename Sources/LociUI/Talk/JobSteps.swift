import LociModel
import SwiftUI

/// The work of making an item readable, as the steps its card names. Reading what a link is and taking the
/// text out of a page are one step to the person: fetching.
enum JobSteps {
  enum Step: Equatable {
    case fetch, extract, cover, download, recognize, diarize, translate, outline, tidy

    init(_ stage: Job.Stage, separateArticleStages: Bool = false) {
      switch stage {
      case .resolve, .fetchPage: self = .fetch
      case .extract: self = separateArticleStages ? .extract : .fetch
      case .findCover: self = .cover
      case .download: self = .download
      case .transcribe: self = .recognize
      case .diarize: self = .diarize
      case .translate: self = .translate
      case .outline: self = .outline
      case .tidy: self = .tidy
      }
    }

    var name: LocalizedStringResource {
      switch self {
      case .fetch: .loci("job.fetching")
      case .extract: .loci("stage.extract")
      case .cover: .loci("stage.findCover")
      case .download: .loci("job.downloading")
      case .recognize: .loci("job.recognizing")
      case .diarize: .loci("job.separatingSpeakers")
      case .translate: .loci("job.translating")
      case .outline: .loci("job.outlining")
      case .tidy: .loci("job.tidying")
      }
    }
  }

  /// The steps an item of this kind goes through, in order.
  static func steps(for kind: Item.Kind) -> [Step] {
    switch kind {
    case .article, .paper, .repository, .book: [.fetch]
    case .video: [.fetch, .download, .recognize, .translate, .outline]
    case .audio: [.fetch, .download, .recognize, .diarize, .translate, .outline]
    }
  }

  /// How far along the whole job is, from 0 to 1.
  static func progress(of job: Job, kind: Item.Kind) -> Double {
    let separate = kind == .article && !job.stages.isEmpty
    let steps = separate ? job.stages.map { Step($0, separateArticleStages: true) } : steps(for: kind)
    guard let index = steps.firstIndex(of: Step(job.stage, separateArticleStages: separate)) else { return 0 }
    let within: Double =
      switch job.state {
      case .done: 1
      case .running(let progress?, _): progress.value
      default: 0
      }
    return (Double(index) + within) / Double(steps.count)
  }

}
