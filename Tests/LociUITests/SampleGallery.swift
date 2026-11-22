import Foundation
import LociModel

@testable import LociUI

extension SampleLibrary {
  func named(_ prefix: String) throws -> EntityID {
    guard let item = items.first(where: { $0.title.hasPrefix(prefix) }) else { throw Missing(title: prefix) }
    return item.id
  }

  struct Missing: Error {
    let title: String
  }

  var uring: EntityID {
    get throws { try named("io_uring") }
  }

  /// The gallery the design draws: a video downloading, a podcast paused, one waiting for a sign-in, one
  /// waiting for a speech model, one failed and one queued; two articles without a picture show as paper.
  func withGalleryWork() throws -> SampleLibrary {
    var library = self
    let video: [Job.Stage] = [.resolve, .download, .transcribe, .translate]
    let audio: [Job.Stage] = [.resolve, .download, .transcribe, .translate]
    library.jobs = [
      Job(
        item: try uring, stage: .download,
        state: .running(progress: Fraction(0.62), amount: Job.Amount(done: 254_000_000, total: 412_000_000)),
        stages: video),
      Job(item: try named("大模型"), stage: .transcribe, state: .paused(progress: Fraction(0.41)), stages: audio),
      Job(item: try named("图解 eBPF"), stage: .resolve, state: .waiting(.login(site: "bilibili.com")), stages: video),
      Job(
        item: try named("Let's build"), stage: .transcribe, state: .waiting(.speechModel(.largeV3TurboQuantized)),
        stages: video),
      Job(item: try named("Linux Systems"), stage: .resolve, state: .queued, stages: video),
      Job(item: try named("Rack-scale"), stage: .translate, state: .running(progress: Fraction(0.35)), stages: audio),
    ]
    library.covers[try named("Attention")] = nil
    library.covers[try named("The Log")] = nil
    return library
  }

  /// Four videos and episodes on the disk, one that plays online, and two speech models.
  func withStorage() throws -> SampleLibrary {
    var library = self
    let sizes: [(String, Bool, Int64?)] = [
      ("Scheduling at Scale", false, 198_000_000), ("io_uring", false, 214_000_000),
      ("Why Inference", true, 96_000_000), ("Turning the Database", false, nil),
    ]
    library.storage = StorageReport(
      capacity: 494_000_000_000, available: 210_000_000_000,
      items: try sizes.map { ItemSpace(item: try named($0.0), isAudio: $0.1, bytes: $0.2, fromLink: true) },
      speechModels: [
        ModelSpace(model: .largeV3TurboQuantized, bytes: 574_000_000), ModelSpace(model: .tiny, bytes: 78_000_000),
      ], sourceCacheBytes: 24_000_000)
    return library
  }
}
