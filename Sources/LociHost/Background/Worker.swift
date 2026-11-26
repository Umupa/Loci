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
    /// Its home was archived or deleted, or for a review kept out of memory: its events wait to be done again.
    var closed = false
    /// The run's hold on its home; once it no longer holds, the run writes nothing there. `nil` for the moment
    /// before it is taken.
    var ticket: HomeTicket?
    /// What the app worked out for a daily review.
    var brief: ReviewBrief?
    /// For a repair, the one source it may save, granted as the run started.
    var repair: RepairGrant?

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

  /// Says a line as the companion in a conversation, on its own.
  let tell: @Sendable (String, ConversationRef) async -> Void
  /// Says a line as the companion in a conversation as the message with the id, kept in the same write as what
  /// it is given to keep with it: see `LociAgent.say`.
  let say: Say

  typealias Say =
    @Sendable (String, ConversationRef, EntityID, @escaping LociAgent.Closing) async throws(HostError) ->
    Void

  init(
    context: AgentContext, talking: @escaping @Sendable () async -> Bool,
    tell: @escaping @Sendable (String, ConversationRef) async -> Void = { _, _ in },
    say: @escaping Say = { _, _, _, closing throws(HostError) in try attempt { try closing(nil) } }
  ) {
    self.context = context
    self.talking = talking
    self.tell = tell
    self.say = say
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

  /// Whether the run's home was closed under it: its session may do nothing more.
  func isClosed(_ run: Run.ID) -> Bool {
    current.map { $0.run.id == run && $0.closed } ?? false
  }

  /// What the run's session may touch, read at once: its policy, its home, and for a repair what it may save.
  /// `nil` once the run is over.
  func access(of run: Run.ID) -> RunAccess? {
    guard let current, current.run.id == run, !current.stopped else { return nil }
    return RunAccess(policy: current.policy, home: current.home, repair: current.repair)
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

  /// The home was archived or deleted: the run under way there stops, and its events wait for the home to open
  /// again.
  func homeClosed(_ home: Home) {
    guard var current, current.home == home else { return }
    stop(&current)
  }

  /// The project was kept out of memory: its review under way stops, and waits for it to be remembered again.
  func reviewStopped(in home: Home) {
    guard var current, current.home == home, current.policy == .review else { return }
    stop(&current)
  }

  private func stop(_ current: inout Current) {
    current.stopped = true
    current.closed = true
    if let agent = current.agent { Task { await agent.stop() } }
    self.current = current
  }

  /// Returns once no run of the home is under way.
  func quiet(_ home: Home) async {
    while let current, current.home == home, let work { await work.value }
  }

  /// Starts the next run when one can start. Returns at once; the run goes on in the background.
  func consider() async {
    guard current == nil, !closing else { return }
    let busy = await talking()
    guard current == nil, !closing else { return }
    let now = context.environment.now()
    let leaving = await context.life.projectsLeaving
    guard current == nil, !closing else { return }
    let ready = ((try? context.database.openEvents()) ?? []).filter { event in
      if let project = event.source.home.project, leaving.contains(project) { return false }
      guard case .waiting(let retry) = event.state else { return false }
      return retry?.notBefore.map { $0 <= now } ?? true
    }
    let wanted = ready.filter { event in
      switch context.isWanted(event) {
      case .now: return true
      case .later: return false
      case .never:
        try? context.database.update(event.with(.dropped))
        return false
      }
    }
    if let asked = wanted.first(where: \.isAsked) {
      await start([asked], at: now)
    } else if !busy, let first = wanted.first {
      await start(Self.together(wanted, first: first), at: now)
    }
  }

  /// The events that share a run with `first`: those of its home raised for the first time, due in the same
  /// minute. A review, a repair, a follow-up, and a run being tried again, run alone.
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
    let repair = context.repairGrant(of: kind, run: id)
    current = Current(
      run: run, events: events, tries: tries, title: titles.joined(separator: "、"), panels: context.panels(of: kind),
      ticket: nil, repair: repair)
    if let repair { await context.commits.open(repair) }
    try? context.database.saveRun(run)
    for event in events { try? context.database.update(event.with(.running(id, tries: tries))) }
    let ticket = await context.ticket(for: kind.home)
    current?.ticket = ticket
    let panels = refreshingPanels
    let opened = await context.steadily {
      guard await context.holds(ticket) else { return false }
      if begun == nil {
        let header = RunRecord.header(
          run, events: events.map { context.describe($0) }, tries: tries, in: context.environment.timeZone)
        try? context.store.saveRunRecord(header, at: run.record)
      }
      if !panels.isEmpty {
        _ = try? context.store.home(kind.home).changePanelState { state in
          for panel in panels { state.refreshed[panel.name] = now }
        }
      }
      return true
    }
    if !opened {
      current?.stopped = true
      current?.closed = true
    }
    if opened, case .review(let day, let project) = kind {
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
      guard current?.stopped != true else { throw .invalidRequest(ToolGateway.stopped) }
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

  private func finish(_ run: Run, _ said: RunResult) async {
    guard let current else { return }
    let mended = if let repair = current.repair { await context.commits.close(repair) } else { false }
    let result = judged(said, of: current, mended: mended)
    let isReview = current.run.kind.sources.contains { if case .review = $0 { true } else { false } }
    if closing {
      if case .review(let day, nil) = run.kind { try? context.database.forgetReview(of: day) }
      if isReview { try? context.store.home(run.kind.home).setMemoryWritable(false) }
      return
    }
    await context.steadily { await self.keep(run, result, of: current) }
    self.current = nil
    work = nil
    await context.follower.follow(changes(of: run.kind))
    await consider()
  }

  /// Keeps what the run came to, with no project closing or moving meanwhile. A run whose home closed under it,
  /// or a review of a project kept out of memory since, keeps nothing in the home and leaves its events to be
  /// done again. A repair that mended its source and a follow-up that finished say how it went in their
  /// conversation.
  private func keep(_ run: Run, _ result: RunResult, of current: Current) async {
    let database = context.database
    let now = context.environment.now()
    let isReview = current.run.kind.sources.contains { if case .review = $0 { true } else { false } }
    let review: Day? = if case .review(let day, nil) = run.kind { day } else { nil }
    let tries = current.tries + 1
    let holds = if let ticket = current.ticket { await context.holds(ticket) } else { false }
    let forgotten = if case .review(_, let project?) = run.kind { !context.isRemembered(project) } else { false }
    guard !current.closed, holds, !forgotten else {
      if isReview, context.isThere(run.kind.home) { try? context.store.home(run.kind.home).setMemoryWritable(false) }
      try? database.saveRun(run.with(.failed("stopped: its project was closed", tries: tries)))
      for event in current.events { try? database.update(event.with(.waiting(nil))) }
      if let review { try? database.forgetReview(of: review) }
      return
    }
    var record = (try? context.store.runRecord(at: run.record)).flatMap(\.self) ?? ""
    if isReview { tidyMemory(of: run.kind.home, after: result, brief: current.brief) }
    let (result, said) = await sayWhatItFound(run, result, of: current)
    switch result {
    case .finished(let reply, let sources):
      let summary = RunResult.summary(of: reply)
      if !said {
        if current.repair != nil { await tell(summary, run.kind.home.conversation) }
        try? database.close(
          run.with(.finished(summary: summary, sources: sources)), events: current.events.map { $0.with(.done(run.id)) }
        )
      }
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
    let retried = if case .failed(_, let again) = result { again && tries < Run.tries } else { false }
    if !retried {
      let done = if case .finished = result { true } else { false }
      context.settleOffers(of: current.panels, in: run.kind.home, run: run.id, done: done, at: now)
    }
    let calls = (try? database.connectorCalls(by: .run(run.id))) ?? []
    if case .finished = result { record += RunRecord.connectors(calls) }
    try? context.store.saveRunRecord(record, at: run.record)
    try? database.indexTranscript(run.record, from: context.store)
  }

  /// Stops the run under way. Its events stay in the inbox and are done again when the app next opens.
  func close() async {
    closing = true
    await current?.agent?.close()
    await work?.value
  }
}
