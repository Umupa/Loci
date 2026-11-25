import Foundation
import LociModel
import LociStore

/// The one background worker: it takes events from the inbox and does them, one run at a time, each in a
/// new session no conversation shows. Events due in the same minute share a run. While the person is
/// talking it starts nothing, except a panel's refresh the person asked for.
actor Worker {
  let context: AgentContext
  /// Whether a turn is running in any conversation.
  private let talking: @Sendable () async -> Bool
  private var current: Current?
  private var work: Task<Void, Never>?
  private var closing = false

  /// How long a failed try waits before the next, after the first, second and third failure.
  static let retryMinutes: [Int64] = [1, 5, 15]

  struct Current {
    var run: Run
    let events: [Event]
    /// Tries that failed before this one.
    let tries: Int
    let title: String
    /// The panels of the run's home it may save, by name.
    var panels: Set<String>
    var agent: AgentRun?
    var stopped = false
    /// What the app worked out for a daily review.
    var brief: ReviewBrief?

    var policy: RunPolicy {
      switch run.kind {
      case .review: .review
      case .timers(let timed):
        if timed.first.repair != nil {
          .repair
        } else if timed.sources.allSatisfy({ $0.panel != nil }) {
          .panel
        } else {
          .timers
        }
      }
    }

    var home: Home { run.kind.home }
  }

  init(context: AgentContext, talking: @escaping @Sendable () async -> Bool) {
    self.context = context
    self.talking = talking
  }

  /// What the run under way is doing, for the line under the companion's name.
  var status: LociWork? {
    guard let current else { return nil }
    switch current.run.kind {
    case .review: return .reviewing
    case .timers(let timed):
      if case .panel = timed.first { return .refreshing(title: current.title) }
      return .looking(title: current.title)
    }
  }

  var refreshingPanels: Set<PanelRef> {
    guard let current, case .timers(let timed) = current.run.kind else { return [] }
    return Set(timed.sources.compactMap(\.panel).filter { current.panels.contains($0.name) })
  }

  /// The home of the run, while it is under way.
  func home(of run: Run.ID) -> Home? {
    current.flatMap { $0.run.id == run ? $0.home : nil }
  }

  /// What the run's session may do with `loci`; `nil` once the run is over.
  func policy(of run: Run.ID) -> RunPolicy? {
    current.flatMap { $0.run.id == run && !$0.stopped ? $0.policy : nil }
  }

  /// The source the run mends, while it is under way.
  func repairing(in run: Run.ID) -> SourceKey? {
    guard let current, current.run.id == run, !current.stopped, case .timers(let timed) = current.run.kind else {
      return nil
    }
    return timed.first.repair
  }

  /// Whether the run may save the panel now.
  func permission(toSave panel: PanelRef, from run: Run.ID) -> PanelPermission {
    guard let current, current.run.id == run, !current.stopped else { return .stopped }
    guard panel.home == current.home, current.panels.contains(panel.name) else {
      return current.policy == .review ? .none : .only(current.panels.sorted())
    }
    return .allowed
  }

  /// A removed panel can no longer be saved by the run under way; a run that was only for it stops.
  func panelRemoved(_ panel: PanelRef) {
    guard var current, current.home == panel.home, current.panels.contains(panel.name) else { return }
    current.panels.remove(panel.name)
    if current.panels.isEmpty, current.policy == .panel {
      current.stopped = true
      if let agent = current.agent { Task { await agent.stop() } }
    }
    self.current = current
  }

  /// Starts the next run when one can start. Returns at once; the run goes on in the background.
  func consider() async {
    guard current == nil, !closing else { return }
    let busy = await talking()
    guard current == nil, !closing else { return }
    let now = context.environment.now()
    let ready = ((try? context.database.openEvents()) ?? []).filter { event in
      guard case .waiting(let retry) = event.state else { return false }
      return retry?.notBefore.map { $0 <= now } ?? true
    }
    let wanted = ready.filter { event in
      if context.isWanted(event) { return true }
      try? context.database.update(event.with(.dropped))
      return false
    }
    if let asked = wanted.first(where: \.isAsked) {
      await start([asked], at: now)
    } else if !busy, let first = wanted.first {
      await start(Self.together(wanted, first: first), at: now)
    }
  }

  /// The events that share a run with `first`: those of its home raised for the first time, due in the same
  /// minute. A review, a repair, and a run being tried again, run alone.
  static func together(_ events: [Event], first: Event) -> [Event] {
    guard case .waiting(nil) = first.state, !first.runsAlone else { return [first] }
    let minute = first.due.millisecondsSince1970 / 60_000
    return events.filter { event in
      guard case .waiting(nil) = event.state, event.source.home == first.source.home else { return false }
      return !event.runsAlone && !event.isAsked && event.due.millisecondsSince1970 / 60_000 == minute
    }
  }

  private func start(_ events: [Event], at now: Timestamp) async {
    guard let first = events.first else { return }
    let retry: Event.Retry? = if case .waiting(let retry) = first.state { retry } else { nil }
    let tries = retry?.tries ?? 0
    let id = retry?.run ?? context.environment.newID()
    let kind: Run.Kind =
      if case .review(let day, let project) = first.source { .review(day, project: project) } else {
        .timers(Run.Timed(first.source, events.dropFirst().map(\.source)))
      }
    let begun = (try? context.database.run(id)) ?? nil
    let record = HomeFiles.runRecordPath(
      of: id, on: Day(containing: now, in: context.environment.timeZone), in: kind.home)
    let run = (begun ?? Run(id: id, kind: kind, startedAt: now, outcome: .running(tries: tries), record: record))
      .with(.running(tries: tries))
    let titles = events.map { context.title(of: $0.source) }
    current = Current(
      run: run, events: events, tries: tries, title: titles.joined(separator: "、"), panels: context.panels(of: kind))
    try? context.database.saveRun(run)
    for event in events { try? context.database.update(event.with(.running(id, tries: tries))) }
    if begun == nil {
      let header = RunRecord.header(
        run, events: events.map { context.describe($0) }, tries: tries, in: context.environment.timeZone)
      try? context.store.saveRunRecord(header, at: run.record)
    }
    let panels = refreshingPanels
    if !panels.isEmpty {
      _ = try? context.store.home(kind.home).changePanelState { state in
        for panel in panels { state.refreshed[panel.name] = now }
      }
    }
    if case .review(let day, let project) = kind {
      if project == nil, (try? context.database.review(of: day)) == nil {
        try? context.database.beginReview(of: day, at: now)
      }
      current?.brief = ReviewBrief.make(
        for: day, in: kind.home, store: context.store, timeZone: context.environment.timeZone)
      try? context.store.home(kind.home).setMemoryWritable(true)
    }
    work = Task { await self.perform(run, redo: retry != nil) }
    await context.follower.follow(changes(of: kind))
  }

  private func perform(_ run: Run, redo: Bool) async {
    let activity = context.environment.activity("Loci is doing something in the background")
    let result: RunResult
    var usage: ContextUsage?
    do throws(HostError) {
      let owner: SessionOwner = if case .review(let day, nil) = run.kind { .review(day) } else { .run(run.id) }
      let agent = try AgentRun(owner: owner, home: run.kind.home, session: .run(run.id), context: context)
      current?.agent = agent
      try await agent.startOver()
      let text = try RunPrompts(context: context).text(for: run, redo: redo, brief: current?.brief)
      if current?.stopped == true {
        result = .stopped
      } else {
        let purpose: Prompt.Purpose = if case .review(let day, _) = run.kind { .review(day) } else { .run(run.id) }
        try await agent.send(Prompt(text: text, purpose: purpose), saying: text)
        result = current?.stopped == true ? .stopped : RunResult(of: await agent.settle())
        usage = await agent.snapshot.context
      }
      await agent.close()
    } catch {
      result = .failed(String(describing: error), again: false)
    }
    activity.end()
    await finish(run.with(usage: usage), result)
  }

  private func finish(_ run: Run, _ result: RunResult) async {
    guard let current else { return }
    let database = context.database
    let now = context.environment.now()
    let isReview = current.run.kind.sources.contains { if case .review = $0 { true } else { false } }
    let review: Day? = if case .review(let day, nil) = run.kind { day } else { nil }
    if closing {
      if let review { try? database.forgetReview(of: review) }
      if isReview { try? context.store.home(run.kind.home).setMemoryWritable(false) }
      return
    }
    let tries = current.tries + 1
    var record = (try? context.store.runRecord(at: run.record)).flatMap(\.self) ?? ""
    if isReview { tidyMemory(of: run.kind.home, after: result, brief: current.brief) }
    switch result {
    case .finished(let reply, let sources):
      let summary = RunResult.summary(of: reply)
      try? database.saveRun(run.with(.finished(summary: summary, sources: sources)))
      markFed(current.panels, of: run)
      for event in current.events { try? database.update(event.with(.done(run.id))) }
      record += RunRecord.found(reply, summary: summary, sources: sources, tries: tries)
      if let review { try? database.endReview(of: review, .finished) }
    case .stopped:
      try? database.saveRun(run.with(.failed("stopped", tries: tries)))
      for event in current.events { try? database.update(event.with(.dropped)) }
      record += RunRecord.failed(try: tries, "Stopped: the panel it was for was removed.", final: true)
      if let review { try? database.forgetReview(of: review) }
    case .failed(let reason, let again) where again && tries < Run.tries:
      let wait = Self.retryMinutes[current.tries] * 60_000
      let retry = Event.Retry(
        run: run.id, tries: tries, notBefore: Timestamp(millisecondsSince1970: now.millisecondsSince1970 + wait))
      try? database.saveRun(run.with(.running(tries: tries)))
      for event in current.events { try? database.update(event.with(.waiting(retry))) }
      record += RunRecord.failed(try: tries, reason, final: false)
    case .failed(let reason, _):
      try? database.saveRun(run.with(.failed(reason, tries: tries)))
      for event in current.events { try? database.update(event.with(.failed(run.id, reason: reason))) }
      record += RunRecord.failed(try: tries, reason, final: true)
      if let review { try? database.endReview(of: review, .failed(reason)) }
    }
    let calls = (try? database.connectorCalls(by: .run(run.id))) ?? []
    if case .finished = result { record += RunRecord.connectors(calls) }
    try? context.store.saveRunRecord(record, at: run.record)
    try? database.indexTranscript(run.record, from: context.store)
    self.current = nil
    work = nil
    await context.follower.follow(changes(of: run.kind))
    await consider()
  }

  /// The panels of a finished run that follow entries are not offered again what the run was offered.
  private func markFed(_ panels: Set<String>, of run: Run) {
    let files = context.store.home(run.kind.home)
    let fed = panels.filter { files.panel(named: $0)?.panel?.feed != nil }
    guard !fed.isEmpty else { return }
    _ = try? files.changePanelState { state in
      for panel in fed { state.fed[panel] = run.startedAt }
    }
  }

  /// After a daily review: on the first split, keeps any entry the review lost; keeps what the review left to
  /// compare against later; and makes the index and wiki read-only again.
  private func tidyMemory(of home: Home, after result: RunResult, brief: ReviewBrief?) {
    let store = context.store
    if case .finished = result {
      if let entries = brief?.migrating { _ = try? ReviewBrief.keepLost(entries, store: store) }
      try? store.home(home).keepMemory()
    }
    try? store.home(home).setMemoryWritable(false)
  }

  /// Stops the run under way. Its events stay in the inbox and are done again when the app next opens.
  func close() async {
    closing = true
    await current?.agent?.close()
    await work?.value
  }

  private func changes(of kind: Run.Kind) -> Set<ContentChange> {
    let changes: Set<ContentChange> =
      switch kind {
      case .review: [.timers, .review]
      case .timers: [.timers, .loci(.panels)]
      }
    return kind.home == .chat ? changes : changes.union([.projects, .turnEnded(kind.home.conversation)])
  }
}

/// What a run's session may do with `loci`.
enum RunPolicy: Equatable {
  /// Only panels' refreshes: read, save those panels, and put cards on the deck.
  case panel
  /// Schedules and follow-ups: read, set follow-ups, save the panels they keep, and put cards on the deck.
  case timers
  /// The daily review: read, set follow-ups, and say how it feels.
  case review
  /// Mending a source: show, test and save that source only.
  case repair

  func refusal(_ name: String) -> String {
    switch self {
    case .panel:
      "A panel's refresh only reads, saves its own panel and puts cards on the deck; loci cannot run \(name) in it."
    case .timers:
      "A run in the background only reads, sets follow-ups, saves its own panel and puts cards on the deck; loci "
        + "cannot run \(name) in it."
    case .review: "The daily review only reads, sets follow-ups and sets your mood; loci cannot run \(name) in it."
    case .repair: "Mending a source only shows, tests and saves that source; loci cannot run \(name) in it."
    }
  }
}

/// Whether a run may save a panel.
enum PanelPermission: Equatable {
  case allowed
  /// The run is over, or what it was for was removed.
  case stopped
  /// It may save only these.
  case only([String])
  /// It may save none.
  case none
}

extension Event {
  var isAsked: Bool {
    if case .panel(_, asked: true, _) = source { true } else { false }
  }

  var isReview: Bool {
    if case .review = source { true } else { false }
  }

  /// A review or a repair, which shares its run with nothing.
  var runsAlone: Bool {
    isReview || source.repair != nil
  }
}
