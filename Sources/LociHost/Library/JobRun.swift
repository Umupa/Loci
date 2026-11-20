import Foundation
import LociMedia
import LociModel
import LociStore

/// One item's job, run stage after stage until it is done, waits for something, fails or is paused.
/// Each stage first looks at what the files already hold, so running a stage twice does no harm.
struct JobRun: Sendable {
  let item: EntityID
  let context: LibraryContext
  let queue: JobQueue

  /// Runs from `first` on. The stages left are read again after each one, since resolving or reading a link
  /// can find it is something else than its address told.
  func run(from first: Job.Stage) async {
    guard var current = try? context.store.item(item) else {
      await queue.forget(item)
      return
    }
    var last = first
    var next = Self.stage(in: stages(of: current), from: first, after: false)
    while let stage = next {
      if Task.isCancelled { return }
      await queue.report(item, stage: stage, state: .running(progress: nil))
      do throws(StageStop) {
        try await perform(stage)
      } catch {
        if Task.isCancelled { return }
        switch error {
        case .wait(let need): await queue.report(item, stage: stage, state: .waiting(need))
        case .fail(let failure): await queue.report(item, stage: stage, state: .failed(failure))
        }
        return
      }
      if Task.isCancelled { return }
      await context.notify([.item(item)])
      last = stage
      guard let now = try? context.store.item(item) else { break }
      current = now
      next = Self.stage(in: stages(of: current), from: stage, after: true)
    }
    await queue.report(item, stage: last, state: .done)
  }

  private func stages(of item: Item) -> [Job.Stage] {
    Job.Stage.all(for: item, choice: context.choice(of: item.id))
  }

  /// The stage of `stages` at `stage`, or the one after it. A stage the item no longer goes through, such
  /// as reading an article that turned out to be a video, is placed by the order stages are declared in.
  static func stage(in stages: [Job.Stage], from stage: Job.Stage, after: Bool) -> Job.Stage? {
    if let index = stages.firstIndex(of: stage) {
      let next = after ? index + 1 : index
      return stages.indices.contains(next) ? stages[next] : nil
    }
    let order = Job.Stage.allCases
    let start = order.firstIndex(of: stage) ?? 0
    return stages.first { (order.firstIndex(of: $0) ?? 0) > start }
  }

  private func perform(_ stage: Job.Stage) async throws(StageStop) {
    let current = try stored { try context.store.item(item) }
    switch stage {
    case .resolve: try await resolve(current)
    case .extract: try await extract(current)
    case .download: try await download(current)
    case .transcribe: try await transcribe(current)
    case .translate: try await translate(current)
    case .outline: try await outline(current)
    }
  }

  /// Runs `body` once `gate` lets it through, showing the job as queued until then.
  func inTurn<Value: Sendable>(
    _ gate: Gate, at stage: Job.Stage, _ body: () async throws(StageStop) -> Value
  ) async throws(StageStop) -> Value {
    await queue.report(item, stage: stage, state: .queued)
    return try await gate.through { () async throws(StageStop) -> Value in
      await queue.report(item, stage: stage, state: .running(progress: nil))
      return try await body()
    }
  }

  func progress(_ stage: Job.Stage) -> @Sendable (Fraction?) -> Void {
    { [queue, item] share in Task { await queue.progress(item, stage: stage, share) } }
  }

  /// How far a download has got, with its bytes.
  func downloadProgress() -> @Sendable (Fraction?, Job.Amount?) -> Void {
    { [queue, item] share, amount in Task { await queue.progress(item, stage: .download, share, amount: amount) } }
  }

  /// The first stage whose file is missing, for an item that has no job.
  static func firstStage(of item: Item, in store: Store) throws -> Job.Stage? {
    let choice = try store.importChoice(of: item.id)
    for stage in Job.Stage.all(for: item, choice: choice) where try !isFinished(stage, of: item, in: store) {
      return stage
    }
    return nil
  }

  private static func isFinished(_ stage: Job.Stage, of item: Item, in store: Store) throws -> Bool {
    switch stage {
    case .resolve:
      return try store.mediaFile(of: item.id) != nil || store.workFile(named: info, of: item.id) != nil
        || store.transcript(of: item.id) != nil
    case .download:
      return try store.mediaFile(of: item.id) != nil
    case .extract:
      return item.kind == .paper ? (try? store.pdf(of: item.id)) != nil : try store.fetchedContent(of: item.id) != nil
    case .transcribe:
      return try store.transcript(of: item.id) != nil
    case .translate:
      guard let transcript = try store.transcript(of: item.id), !transcript.segments.isEmpty else { return true }
      return try store.translations(of: item.id).contains { $0.fits(transcript) }
    case .outline:
      guard let transcript = try store.transcript(of: item.id), !transcript.segments.isEmpty else { return true }
      return try store.outline(of: item.id) != nil
    }
  }
}
