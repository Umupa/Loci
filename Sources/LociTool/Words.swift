import Foundation
import LociModel

/// The short texts the command prints, for Loci to read.
enum Words {
  static func hit(_ hit: SearchHit, titles: [EntityID: String]) -> String {
    let item: EntityID
    let note: String
    switch hit.target {
    case .item(let id):
      item = id
      note = ""
    case .note(_, on: .lesson(_, let lesson)):
      return "\(lesson)  (the person's lesson note)\n    \(hit.snippet)"
    case .note(_, on: .item(let id)):
      item = id
      note = " (the person's note)"
    }
    let head = "\(item)  \(titles[item] ?? "(no title)")\(note)"
    return hit.field == .title ? head : "\(head)\n    \(hit.snippet)"
  }

  static func item(_ item: Item, job: Job?, folder: String) -> String {
    var lines = [item.title, "id: \(item.id)", "kind: \(kind(item.kind))"]
    if !item.authors.isEmpty { lines.append("authors: \(item.authors.joined(separator: ", "))") }
    if let source = item.source { lines.append("source: \(source.absoluteString)") }
    lines.append("job: \(job.map(state) ?? "done")")
    lines.append("folder: \(folder)")
    return lines.joined(separator: "\n")
  }

  static func saved(_ item: Item) -> String {
    "\(item.id)  \(item.title)\nIn the library now. Run `loci wait \(item.id)` before reading it."
  }

  /// Whether a job has stopped moving by itself: finished, failed, paused, or waiting for the person.
  static func isSettled(_ state: Job.State) -> Bool {
    switch state {
    case .queued, .running: false
    case .waiting, .failed, .paused, .done: true
    }
  }

  static func outcome(of job: Job?, item: EntityID) -> String {
    guard let job, job.state != .done else { return "\(item) is ready." }
    return "\(item): \(state(job))"
  }

  private static func state(_ job: Job) -> String {
    let stage = stage(job.stage)
    switch job.state {
    case .queued: return "queued to start \(stage)"
    case .running(let progress?, _): return "\(stage), \(Int((progress.value * 100).rounded()))%"
    case .running(nil, _): return stage
    case .waiting(let need): return "waiting while \(stage): \(Self.need(need))"
    case .failed(let failure): return "failed while \(stage): \(failure.reason)" + remedy(failure.remedy)
    case .paused: return "paused while \(stage); the person can resume it in the library"
    case .done: return "done"
    }
  }

  private static func stage(_ stage: Job.Stage) -> String {
    switch stage {
    case .resolve: "reading the link"
    case .fetchPage: "fetching the page"
    case .findCover: "finding a cover"
    case .extract: "taking the text out of the page"
    case .download: "downloading"
    case .transcribe: "transcribing"
    case .diarize: "separating speakers"
    case .translate: "translating"
    case .outline: "finding chapters"
    case .tidy: "tidying the article"
    }
  }

  private static func need(_ need: Job.Need) -> String {
    switch need {
    case .component(let component):
      "it needs \(component.rawValue); the person can install it in Settings › Media"
    case .speechModel(let model):
      "it needs the \(model.rawValue) speech model; the person can download it in Settings › Media"
    case .login(let site): "\(site) wants a signed-in visitor; the person can sign in from the built-in browser"
    case .modelService: "no model service is configured for it; the person can set one up in Settings › Model Services"
    }
  }

  private static func remedy(_ remedy: Job.Remedy?) -> String {
    switch remedy {
    case .updateComponent(let component): ". Updating \(component.rawValue) in Settings › Media may help."
    case .retry: ". Retrying it in the library may help."
    case .chooseBrowserLogin: ". The person can choose a browser to sign in with in Settings › Media."
    case .openSource: ". The original page may say why."
    case nil: ""
    }
  }

  private static func kind(_ kind: Item.Kind) -> String {
    switch kind {
    case .article: "article"
    case .paper: "paper"
    case .video(let duration): "video" + length(duration)
    case .audio(let duration): "audio" + length(duration)
    case .repository(let commit): "repository at \(commit)"
    case .book: "book"
    }
  }

  private static func length(_ duration: Duration?) -> String {
    guard let duration else { return "" }
    let seconds = Int(duration.components.seconds)
    return String(format: ", %d:%02d", seconds / 60, seconds % 60)
  }
}
