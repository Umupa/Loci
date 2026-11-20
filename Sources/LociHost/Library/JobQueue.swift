import Foundation
import LociModel
import LociStore
import os

/// Every item's job: which are queued, running, waiting or paused, and the work under way.
///
/// Stage changes are written to the database as they happen, so a job carries on after the app quits;
/// progress within a stage is kept in memory only. Recognition runs one at a time, downloads two, agent
/// stages one; resolving a link never waits, so a pasted video can play at once.
actor JobQueue {
  private let context: LibraryContext
  private var jobs: [EntityID: Job] = [:]
  /// The jobs of items deleted a moment ago, as they stood.
  private var setAside: [EntityID: Job] = [:]
  private var work: [EntityID: (task: Task<Void, Never>, generation: Int)] = [:]
  private var started = 0
  private var closing = false
  /// What Loci saved while any of it still had work going on.
  private var saving: [EntityID] = []
  let gates = Gates()

  init(context: LibraryContext) {
    self.context = context
  }

  struct Gates {
    let recognition = Gate(limit: 1)
    let downloads = Gate(limit: 2)
    let agents = Gate(limit: 1)
  }

  /// Picks up every job that was not finished, paused or failed when the app last quit.
  func resume() {
    let saved: [Job]
    do {
      saved = try context.database.jobs()
    } catch {
      Logger(subsystem: "Loci", category: "library").error(
        "could not read jobs: \(String(describing: error), privacy: .public)")
      return
    }
    for job in saved {
      jobs[job.item] = Job(item: job.item, stage: job.stage, state: job.state, stages: stages(of: job.item))
      switch job.state {
      case .queued, .running, .waiting: start(job.item, at: job.stage)
      case .failed, .paused, .done: continue
      }
    }
  }

  /// Stops all work without marking it paused, so it carries on next time.
  func close() async {
    closing = true
    let running = work.values.map(\.task)
    for task in running { task.cancel() }
    for task in running { await task.value }
  }

  var all: [Job] {
    jobs.values.filter { $0.state != .done }.sorted { $0.item < $1.item }
  }

  func job(of item: EntityID) -> Job? {
    jobs[item].flatMap { $0.state == .done ? nil : $0 }
  }

  /// Starts a new job at its first stage.
  func begin(_ item: EntityID, at stage: Job.Stage) async {
    await set(Job(item: item, stage: stage, state: .queued))
    start(item, at: stage)
  }

  /// Starts the job again where it was paused, failed or waits; an item without one starts where its files
  /// say it should. A job already running is left alone.
  func retry(_ item: EntityID, firstStage: () throws -> Job.Stage?) async throws -> Job {
    if let running = work[item], !running.task.isCancelled, let job = jobs[item], job.state != .done { return job }
    let stage: Job.Stage
    if let job = jobs[item], job.state != .done {
      stage = job.stage
    } else if let first = try firstStage() {
      stage = first
    } else {
      throw HostError.invalidRequest("nothing is left to do for this item")
    }
    await set(Job(item: item, stage: stage, state: .queued))
    start(item, at: stage)
    return jobs[item] ?? Job(item: item, stage: stage, state: .queued)
  }

  /// Pauses the job and keeps what it made, a download's part among it; nothing when there is no work.
  func pause(_ item: EntityID) async {
    guard let job = jobs[item], job.state != .done else { return }
    work[item]?.task.cancel()
    work[item] = nil
    let progress: Fraction? = if case .running(let progress, _) = job.state { progress } else { nil }
    await set(job.with(.paused(progress: progress)))
  }

  /// Starts again every job waiting for something that `met` says is there now.
  func wake(where met: (Job.Need) -> Bool) {
    for job in jobs.values {
      guard case .waiting(let need) = job.state, met(need), work[job.item] == nil else { continue }
      start(job.item, at: job.stage)
    }
  }

  /// Stops the job of an item being deleted, keeping where it was so `putBack` can carry on from there.
  func setAside(_ item: EntityID) {
    work[item]?.task.cancel()
    work[item] = nil
    if let job = jobs.removeValue(forKey: item) { setAside[item] = job }
  }

  /// Carries on with the job of an item brought back, as it stood when it was set aside.
  func putBack(_ item: EntityID) async {
    guard let job = setAside.removeValue(forKey: item) else { return }
    await set(job)
    switch job.state {
    case .queued, .running, .waiting: start(item, at: job.stage)
    case .failed, .paused, .done: break
    }
  }

  /// Forgets the job of an item that is gone.
  func forget(_ item: EntityID) async {
    setAside[item] = nil
    work[item]?.task.cancel()
    work[item] = nil
    jobs[item] = nil
    try? context.database.deleteJob(of: item)
  }

  private func start(_ item: EntityID, at stage: Job.Stage) {
    guard !closing else { return }
    work[item]?.task.cancel()
    started += 1
    let generation = started
    let run = JobRun(item: item, context: context, queue: self)
    work[item] = (
      Task { [weak self] in
        await run.run(from: stage)
        await self?.ended(item, generation: generation)
      }, generation
    )
  }

  /// A stage began, or the job moved to another state; written down. A job that was paused or closed
  /// meanwhile reports nothing more.
  func report(_ item: EntityID, stage: Job.Stage, state: Job.State) async {
    guard !Task.isCancelled else { return }
    let job = Job(item: item, stage: stage, state: state, stages: stages(of: item))
    guard jobs[item] != job else { return }
    await set(job)
  }

  /// How far the running stage has got. Kept in memory only, told when it moves a whole percent, and
  /// dropped when the job has moved on since.
  func progress(_ item: EntityID, stage: Job.Stage, _ share: Fraction?, amount: Job.Amount? = nil) async {
    guard let job = jobs[item], job.stage == stage, case .running(let before, _) = job.state,
      Equipment.moved(from: before, to: share)
    else { return }
    jobs[item] = job.with(.running(progress: share, amount: amount))
    await context.notify([.job(item)])
  }

  /// The job's task has ended, whichever way. A later start of the same job is left alone.
  private func ended(_ item: EntityID, generation: Int) {
    if work[item]?.generation == generation { work[item] = nil }
  }

  /// The stages the item goes through, as its files and the choice it was taken in with say now; none for an
  /// item that is gone.
  private func stages(of item: EntityID) -> [Job.Stage] {
    guard let found = try? context.store.item(item) else { return [] }
    return Job.Stage.all(for: found, choice: context.choice(of: item))
  }

  /// Adds an item Loci saved to the batch it is saving; an item with no work is left out.
  func joinSaving(_ item: EntityID) {
    guard let job = jobs[item], Self.isGoing(job.state), !saving.contains(item) else { return }
    saving.append(item)
  }

  var savingBatch: SavingBatch? {
    guard !saving.isEmpty else { return nil }
    let finished = saving.count { jobs[$0].map { !Self.isGoing($0.state) } ?? true }
    return SavingBatch(items: saving, finished: finished)
  }

  /// The batch's items still waiting their turn before anything readable is made of them: their text, their
  /// transcript or their media.
  var notStarted: [EntityID] {
    saving.filter { item in
      guard let job = jobs[item], job.state == .queued else { return false }
      return [.resolve, .extract, .transcribe, .download].contains(job.stage)
    }
  }

  private static func isGoing(_ state: Job.State) -> Bool {
    switch state {
    case .queued, .running: true
    case .waiting, .failed, .paused, .done: false
    }
  }

  /// Ends the batch once none of it has work going on.
  private func settleSaving() {
    if !saving.isEmpty, !saving.contains(where: { jobs[$0].map { Self.isGoing($0.state) } ?? false }) {
      saving = []
    }
  }

  private func set(_ job: Job) async {
    let job =
      job.stages.isEmpty ? Job(item: job.item, stage: job.stage, state: job.state, stages: stages(of: job.item)) : job
    jobs[job.item] = job
    settleSaving()
    do {
      if job.state == .done {
        try context.database.deleteJob(of: job.item)
      } else {
        try context.database.save(job, at: context.now())
      }
    } catch {
      Logger(subsystem: "Loci", category: "library").error(
        "could not save a job: \(String(describing: error), privacy: .public)")
    }
    await context.notify([.job(job.item)])
  }
}
