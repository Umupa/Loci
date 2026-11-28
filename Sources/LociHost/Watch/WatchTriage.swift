import Foundation
import LociModel
import LociStore

/// Watch triage: each batch a source's fetch brought that is new is read once by the tool model, against the
/// home's `WATCH.md`, and dropped, shown in a panel that follows the source, or raised as a watch finding the
/// companion is woken for. It asks the model directly, as translation does, and never takes the worker: a
/// fetch, a run under way and another home's triage all go on while it waits. A home's batches are read one at
/// a time, the oldest first, each with the fetch before it, so a number's crossing is judged against that
/// fetch; one waiting to be tried again holds back none after it. At most `most` homes at once. Without a tool
/// model the batches wait, kept, until one is set.
actor WatchTriage {
  /// The most homes whose batches are read at once.
  static let most = 4

  private let context: AgentContext
  private let panels: PanelKeeper
  private let worker: Worker
  /// One call to the tool model; `nil` while there is none to call.
  private let answer: @Sendable (String) async throws -> String?
  private var reading: [Home: Task<Void, Never>] = [:]
  private var closing = false

  init(
    context: AgentContext, panels: PanelKeeper, worker: Worker,
    answer: @escaping @Sendable (String) async throws -> String?
  ) {
    self.context = context
    self.panels = panels
    self.worker = worker
    self.answer = answer
  }

  /// Starts reading the oldest batch of each open home that is not being read, as far as `most` allows.
  func look() {
    guard !closing, reading.count < Self.most, let waiting = try? context.database.waitingWatchBatches() else {
      return
    }
    let homes = Set(context.homes())
    let now = context.environment.now()
    var looked = Set(reading.keys)
    for batch in waiting where reading.count < Self.most {
      let home = batch.batch.source.home
      guard homes.contains(home), batch.notBefore.map({ $0 <= now }) ?? true, looked.insert(home).inserted
      else { continue }
      reading[home] = Task {
        await self.finished(home, await self.read(batch))
      }
    }
  }

  /// Returns once no batch is being read, nor one started in the meantime.
  func settled() async {
    while let under = reading.values.first { await under.value }
  }

  func close() async {
    closing = true
    let under = Array(reading.values)
    for task in under { task.cancel() }
    for task in under { await task.value }
  }

  /// What came of reading a batch.
  private enum Reading {
    /// Decided, or given up on.
    case done
    /// To be tried again after its wait; the home's other batches go on meanwhile.
    case later
    /// There is no model to ask, or its home closed under it: it waits for the next minute's look, or for the
    /// model services to change.
    case waits
  }

  private func finished(_ home: Home, _ reading: Reading) async {
    self.reading[home] = nil
    switch reading {
    case .done:
      look()
      await worker.consider()
    case .later: look()
    case .waits: break
    }
  }

  /// A batch is done with once decided, or given up on after `Worker.retryMinutes.count` answers the app could
  /// not read, each tried again after the next of those waits. A call that fails, or what was decided that could
  /// not be kept, is tried again a minute later, for as long as it takes.
  private func read(_ waiting: WaitingWatchBatch) async -> Reading {
    let home = waiting.batch.source.home
    let ticket = await context.ticket(for: home)
    let activity = context.environment.activity("Loci is sorting what a source fetched")
    defer { activity.end() }
    let reply: String
    let shown: [Panel]
    do {
      shown = try followers(of: waiting.batch)
      guard let answered = try await answer(try prompt(for: waiting, panels: shown)) else { return .waits }
      guard !Task.isCancelled else { return .waits }
      reply = answered
    } catch {
      guard !Task.isCancelled else { return .waits }
      await failed(waiting, because: Self.reason(error))
      return .later
    }
    let decisions: [WatchDecision]
    do {
      decisions = try WatchDecision.read(reply, entries: waiting.batch.entries, panels: Set(shown.map(\.name)))
    } catch {
      return await unreadable(waiting, because: Self.reason(error))
    }
    do {
      return try await context.steadily {
        guard await self.context.holds(ticket) else { return .waits }
        try await self.keep(decisions, of: waiting, panels: shown)
        return .done
      }
    } catch {
      await failed(waiting, because: Self.reason(error))
      return .later
    }
  }

  /// Each failure is told to the timers page, which shows a source that keeps failing.
  private func failed(_ waiting: WaitingWatchBatch, because problem: String) async {
    let now = context.environment.now()
    try? context.database.failWatchBatch(
      waiting.id, problem: problem, at: now,
      notBefore: Timestamp(millisecondsSince1970: now.millisecondsSince1970 + Self.callRetryMinutes * 60_000))
    await context.follower.follow([.timers])
  }

  private func unreadable(_ waiting: WaitingWatchBatch, because problem: String) async -> Reading {
    let givenUp = waiting.tries + 1 >= Worker.retryMinutes.count
    if givenUp {
      try? context.database.finishWatchBatch(waiting.id)
    } else {
      let now = context.environment.now()
      try? context.database.retryWatchBatch(
        waiting.id, problem: problem, at: now, notBefore: Self.later(now, after: waiting.tries))
    }
    await context.follower.follow([.timers])
    return givenUp ? .done : .later
  }

  /// When to try again an answer that could not be read, after `failed` such answers before this one.
  private static func later(_ now: Timestamp, after failed: Int) -> Timestamp {
    let minutes = Worker.retryMinutes[min(failed, Worker.retryMinutes.count - 1)]
    return Timestamp(millisecondsSince1970: now.millisecondsSince1970 + minutes * 60_000)
  }

  private static func reason(_ error: any Error) -> String {
    switch HostError(error) {
    case .invalidRequest(let reason), .storage(let reason), .notFound(let reason): reason
    case let other: String(describing: other)
    }
  }

  /// How long a batch whose call failed waits: a model that is down fails the batches after it too, so waiting
  /// longer only delays them once it is back.
  static let callRetryMinutes: Int64 = 1

  /// The model services changed: every batch waiting to be tried again is tried at once.
  func modelsChanged() {
    try? context.database.retryWatchBatchesNow()
    look()
  }

  /// The panels of the home that follow the batch's source and are not paused.
  private func followers(of batch: WatchBatch) throws -> [Panel] {
    let files = context.store.home(batch.source.home)
    let paused = files.panelState().paused
    return files.panels().compactMap(\.panel).filter {
      $0.feed?.source == batch.source.name && !paused.contains($0.name)
    }
  }

  private func prompt(for waiting: WaitingWatchBatch, panels: [Panel]) throws -> String {
    let batch = waiting.batch
    let home = batch.source.home
    let files = context.store.home(home)
    let others = try context.database.sourceSnapshots(
      Set(context.store.dataSources(in: files.sources).map { SourceKey(home, $0.name) }))
    let input = Input(
      watch: try files.watch(), observedAt: batch.snapshot.fetched, timeZone: context.environment.timeZone.identifier,
      source: batch.source.name, title: batch.title, entries: batch.entries, previousRecords: batch.previous?.records,
      records: batch.snapshot.records,
      otherSources: Dictionary(
        uniqueKeysWithValues: others.filter { $0.key != batch.source }.map { ($0.key.name, $0.value.records) }),
      panels: panels.map(\.name), recent: try context.database.recentWatchFindings(in: home, limit: 30))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let material = String(decoding: ExternalContent.json(try encoder.encode(input), from: batch.title), as: UTF8.self)
    let place = home.project.map { "the project projects/\($0)" } ?? "the main conversation"
    return context.prompts.watchTriage.replacing("{{home}}", with: place) + "\n" + material
  }

  /// Keeps what was decided: the panels' picks, each with its sentence and the entries' own titles, links and
  /// times; and each finding raised once for its key, while its deadline is still to come.
  private func keep(_ decisions: [WatchDecision], of waiting: WaitingWatchBatch, panels: [Panel]) async throws {
    let batch = waiting.batch
    let home = batch.source.home
    let files = context.store.home(home)
    let now = context.environment.now()
    var picks: [String: (sentence: String, entries: [SeenEntry])] = [:]
    var raised = false
    for decision in decisions {
      switch decision {
      case .discard: break
      case .panel(let name, let id, let sentence):
        guard let entry = batch.entries.first(where: { $0.id == id }) else { continue }
        picks[name, default: (sentence, [])].entries.append(
          SeenEntry(entry: entry, seen: batch.snapshot.fetched, seq: 0))
      case .escalate(let key, let summary, let reason, let ids, let deadline):
        guard deadline > now else { continue }
        let evidence = batch.entries.filter { ids.contains($0.id) }.map {
          WatchFinding.Evidence(title: $0.title, source: batch.title, at: $0.at ?? batch.snapshot.fetched, link: $0.url)
        }
        let finding = WatchFinding(
          key: key, summary: summary, reason: reason,
          evidence: evidence.isEmpty
            ? [WatchFinding.Evidence(title: batch.title, source: batch.title, at: batch.snapshot.fetched)] : evidence)
        let event = Event(
          id: context.environment.newID(), source: .watch(finding, project: home.project), due: batch.snapshot.fetched,
          deadline: deadline, depth: 1)
        if try context.database.raise(event) { raised = true }
      }
    }
    for panel in panels {
      guard let pick = picks[panel.name] else { continue }
      try self.panels.writeFeed(panel, in: home, sentence: pick.sentence, entries: pick.entries)
      _ = try files.changePanelState { state in
        let ids = pick.entries.map(\.entry.id)
        state.shownEntries[panel.name] = Array(
          (ids + (state.shownEntries[panel.name] ?? []).filter { !ids.contains($0) }).prefix(StoreDatabase.entriesKept))
      }
    }
    try context.database.finishWatchBatch(waiting.id)
    if !picks.isEmpty { await context.follower.follow([.loci(.panels)]) }
    if raised || waiting.problem != nil { await context.follower.follow([.timers]) }
  }

  private struct Input: Encodable {
    let watch: String
    let observedAt: Timestamp
    let timeZone: String
    let source: String
    let title: String
    let entries: [SourceEntry]
    let previousRecords: [String: SourceRecord]?
    let records: [String: SourceRecord]
    let otherSources: [String: [String: SourceRecord]]
    let panels: [String]
    let recent: [WatchFinding]
  }
}
