import Foundation
import LociAgents
import LociModel
import LociStore
import os

/// One owner's turns, a conversation's, a day's review or a panel's refresh, over the agent sessions underneath.
///
/// One turn runs at a time. A turn's prompt is stored as soon as it is sent; the rest is kept in memory while
/// the turn runs and stored together when it ends. A turn the app quit during is stored as stopped when the
/// conversation is next opened. Before each turn the run decides whether the session goes on or a new one
/// starts; the person sees one conversation either way.
actor AgentRun {
  let owner: SessionOwner
  /// What the sessions are for, which says what they run on.
  let work: ModelWork.Session
  /// Where the sessions work, and whose notes and transcripts they keep.
  let home: Home
  let toolSession: LocalSession?
  private var courseToolAccess: EntityID?
  let context: AgentContext
  private var stored: [Message]
  /// The session to go on with; `nil` when there is none, or the person started over.
  private var session: SessionRecord?
  /// Where a prompt is stored while there is no session to go on with, until the agent's session takes it.
  private var holding: SessionRecord?
  private var live: (any AgentSession)?
  private var liveCredentialRevision: Int?
  private var wear = SessionRotation.Wear()
  private var turn: TurnRecord?
  private var running: Task<Void, Never>?
  private var stopping = false
  private var lastTurn: [Message] = []
  /// Lines the companion says on its own, waiting for the turn under way to end.
  private var untold: [String] = []
  /// Lines said and kept while the turn under way ran, shown once it ends, after its prompt as they are kept.
  private var saidDuringTurn: [Message] = []
  /// What the turn did since it was last shown, waiting to be shown with what comes after it.
  private var showing: Task<Void, Never>?

  /// How long what a turn does is held before it is shown, so a reply streaming a word at a time is
  /// shown a few words at a time.
  static let showEvery = Duration.milliseconds(50)

  init(
    owner: SessionOwner, work: ModelWork.Session, home: Home, session: LocalSession?, context: AgentContext
  ) throws(HostError) {
    self.owner = owner
    self.work = work
    self.home = home
    toolSession = session
    self.context = context
    var stored = try attempt { try context.database.messages(of: owner) }
    let session =
      stored.last?.body == .startedOver ? nil : try attempt { try context.database.latestSession(of: owner) }
    if let cut = stored.last, case .prompt = cut.body, let session {
      let stopped = Message(id: context.environment.newID(), at: cut.at, body: .ended(.interrupted))
      try attempt { try context.database.append([stopped], to: session.id) }
      Self.mirror([cut, stopped], of: session, in: home, context: context)
      stored.append(stopped)
    }
    self.stored = stored
    self.session = session
  }

  static let busy = "Your companion is still answering the last message here"

  var isIdle: Bool { turn == nil }

  func acceptsCourseTools(_ access: EntityID) -> Bool {
    turn != nil && !stopping && courseToolAccess == access
  }

  /// What was said, the turn running now, and how full the session's context window last was.
  var snapshot: (messages: [Message], turn: LiveTurn?, context: ContextUsage?) { (stored, turn?.live, wear.usage) }

  /// Starts a turn and returns at once; the turn goes on in the background. Loci is told `text`, which
  /// adds to what the person wrote when they asked about a passage. The person's message is kept as `id` when
  /// given, so whoever asked can tell later whether it was.
  func send(_ prompt: Prompt, saying text: String, as id: EntityID? = nil) async throws(HostError) {
    guard turn == nil else { throw .invalidRequest(Self.busy) }
    let started = TurnRecord(
      prompt: prompt, at: context.environment.now(), id: id ?? context.environment.newID(),
      newID: context.environment.newID)
    try attempt { try context.database.append(started.messages, to: try holdingSession().id) }
    turn = started
    stopping = false
    running = Task { await self.run(text) }
    await changed(ended: false)
  }

  /// Waits for the running turn to end, and gives the messages of the last turn that ended.
  func settle() async -> [Message] {
    await running?.value
    return lastTurn
  }

  /// Stops the running turn and returns once it has ended.
  func stop() async {
    guard turn != nil else { return }
    stopping = true
    await live?.interrupt()
    await running?.value
  }

  /// Leaves a line where the person started over; the next turn opens a fresh session that is not told
  /// what was said before.
  func startOver() async throws(HostError) {
    guard turn == nil else { throw .invalidRequest(Self.busy) }
    guard let last = stored.last, last.body != .startedOver else { return }
    let line = Message(id: context.environment.newID(), at: context.environment.now(), body: .startedOver)
    let record = try attempt { try sessionForStoring() }
    try attempt { try context.database.append([line], to: record.id) }
    mirror([line], of: record)
    stored.append(line)
    session = nil
    await dropLive()
    await changed(ended: true)
  }

  func close() async {
    await stop()
    await dropLive()
  }

  /// Says a line as the companion as the message `id`, kept by `closing` in one write with what goes with it:
  /// see `LociAgent.say`. During a turn it is kept at once and shown when the turn ends.
  func say(_ text: String, as id: EntityID, closing: LociAgent.Closing) async throws(HostError) {
    if try attempt({ try context.database.hasMessage(id) }) {
      try attempt { try closing(nil) }
      return
    }
    let line = Message(id: id, at: context.environment.now(), body: .told(text))
    let record = try attempt { try sessionForStoring() }
    try attempt { try closing((line, record.id)) }
    guard turn == nil else {
      saidDuringTurn.append(line)
      return
    }
    mirror([line], of: record)
    stored.append(line)
    await changed(ended: true)
  }

  /// Says a line in the conversation as the companion, on its own, such as what it mended in the background:
  /// at once, or once the turn under way has ended.
  func tell(_ text: String) async {
    guard turn == nil else {
      untold.append(text)
      return
    }
    let line = Message(id: context.environment.newID(), at: context.environment.now(), body: .told(text))
    do {
      let record = try sessionForStoring()
      try context.database.append([line], to: record.id)
      mirror([line], of: record)
    } catch {
      await context.follower.hub.failed(String(describing: error))
      return
    }
    stored.append(line)
    await changed(ended: true)
  }

  /// Says in the running turn that Loci put an item into the library; nothing when no turn is running.
  func saved(_ item: EntityID) {
    guard turn != nil else { return }
    turn?.saved(item, at: context.environment.now())
    changedSoon()
  }

  private func run(_ text: String) async {
    do throws(TurnFailure) {
      let (agent, opening) = try await openSession()
      if !stopping {
        let said = try await compose(text, opening: opening)
        wear.characters += said.count
        let started = try await TurnFailure.awaiting { () async throws(AgentError) in try await agent.send(said) }
        if stopping { Task { await agent.interrupt() } }
        for await event in started.events {
          if case .permission(let request) = event {
            await agent.answer(request.id, with: Self.allowing(request))
            continue
          }
          record(event)
          if case .ended(.failed(.exited)) = event { await dropLive() }
          changedSoon()
        }
      } else {
        turn?.apply(.ended(.interrupted), at: context.environment.now())
      }
    } catch {
      turn?.end(error.ending, at: context.environment.now())
    }
    await finish()
  }

  private func record(_ event: AgentEvent) {
    switch event {
    case .context(let usage):
      wear.usage = usage
      return
    case .notice(.compacting):
      wear.compacted = true
    case .text(let more), .thinking(let more):
      wear.characters += more.count
    case .toolCallChanged(_, .finished(let output, _)):
      wear.characters += output.count
    default:
      break
    }
    turn?.apply(event, at: context.environment.now())
  }

  /// The message Loci is sent: what changed around it, the item when a session on one starts, what was
  /// said before when a session is renewed, then the text.
  private func compose(_ text: String, opening: SessionRotation.Reason?) async throws(TurnFailure) -> String {
    guard case .conversation(let conversation) = owner, let session else { return text }
    let since = stored.last { $0.isTyped }?.at
    let surroundings = await context.turnContext(for: conversation, since: since)
    let (prefix, shown) = surroundings.prefix(shown: session.sent)
    let remembered = session.with(sent: shown)
    try TurnFailure.from { () throws(HostError) in
      try attempt { try context.database.markSent(shown, in: remembered.id) }
      try attempt { try context.database.markTold(surroundings.told, at: context.environment.now()) }
    }
    self.session = remembered
    var parts = [prefix]
    if opening != nil, case .item(let item) = conversation, let introduction = context.introduction(to: item) {
      parts.append(introduction)
    }
    if case .course(let id) = conversation { parts += context.courseBriefing(id, opening: opening != nil) }
    if let opening, opening.carriesOver, let recap = Recap.of(stored) { parts.append(recap) }
    parts.append(text)
    return parts.joined()
  }

  /// The live session, or a new one when the session cannot go on. Gives why a new one was opened, or `nil`
  /// when the turn goes on in the session it had.
  private func openSession() async throws(TurnFailure) -> (any AgentSession, SessionRotation.Reason?) {
    if case .turn(let conversation) = work { await context.agents.keep(runtimeOf: conversation) }
    let selection = await context.agents.selection(for: work.runsOn)
    let runtime = selection.runtime
    let instructions = try TurnFailure.from { () throws(HostError) in try context.instructions(for: home) }
    let fingerprint = SessionRotation.fingerprint(
      of: instructions + selection.instructionsScope, keptOut: context.knownProjects(from: home))
    var reason = SessionRotation.reason(
      current: session, startedOver: stored.last?.body == .startedOver, wear: wear, runtime: runtime,
      instructions: fingerprint)
    if reason == nil, let live {
      if liveCredentialRevision == selection.credential?.revision { return (live, nil) }
      reason = .runtimeChanged
    }
    await dropLive()
    if reason == nil, session?.handle == nil { reason = .lost }
    guard let driver = await context.agents.driver(for: selection) else {
      throw TurnFailure(.unstarted(runtime.provider, await context.agents.failure(for: runtime.provider)))
    }
    let files = context.store.home(home)
    try TurnFailure.from { () throws(HostError) in
      try attempt {
        try files.writeInstructions(instructions)
        if home != .chat { try files.writeSkill(named: "loci", ToolGuide.skill) }
      }
    }
    var tool = context.tool(for: owner, else: toolSession)
    var configuration = SessionConfiguration(
      workingDirectory: files.folder, model: selection.sessionModel, effort: runtime.effort,
      environment: tool.map { [LocalCall.sessionVariable: $0.tag] } ?? [:])
    if reason == nil, let handle = session?.handle {
      configuration.resume = SessionHandle(provider: runtime.provider, value: handle)
    }
    let opened: any AgentSession
    do {
      opened = try await driver.open(configuration)
    } catch {
      guard error == .sessionNotFound, configuration.resume != nil else {
        throw TurnFailure(starting: runtime.provider, error)
      }
      configuration.resume = nil
      tool = context.tool(for: owner, else: toolSession)
      configuration.environment = tool.map { [LocalCall.sessionVariable: $0.tag] } ?? [:]
      reason = .lost
      do {
        opened = try await driver.open(configuration)
      } catch {
        throw TurnFailure(starting: runtime.provider, error)
      }
    }
    if reason != nil {
      let fresh = SessionRecord(
        id: context.environment.newID(), owner: owner, runtime: runtime, handle: opened.handle.value,
        instructions: fingerprint, startedAt: context.environment.now())
      let database = context.database
      let prompt = turn?.messages.prefix(1).map(\.id) ?? []
      try TurnFailure.from { () throws(HostError) in try attempt { try database.start(fresh, taking: prompt) } }
      session = fresh
      holding = nil
      wear = SessionRotation.Wear()
    }
    live = opened
    liveCredentialRevision = selection.credential?.revision
    if case .course(_, let access) = tool { courseToolAccess = access }
    return (opened, reason)
  }

  private func finish() async {
    guard var turn else { return }
    if case .conversation = owner { await saveAnswer(of: &turn) }
    let said = saidDuringTurn
    saidDuringTurn = []
    let kept = Array(turn.messages.prefix(1)) + said + turn.messages.dropFirst()
    do {
      let record = try sessionForStoring()
      try context.database.append(Array(turn.messages.dropFirst()), to: record.id)
      mirror(kept, of: record)
    } catch {
      await context.follower.hub.failed(String(describing: error))
    }
    stored += kept
    lastTurn = turn.messages
    self.turn = nil
    running = nil
    await changed(ended: true)
    let waiting = untold
    untold = []
    for text in waiting { await tell(text) }
  }

  /// The session to store a turn in. A turn whose agent never started still needs one.
  private func sessionForStoring() throws -> SessionRecord {
    if let session { return session }
    let record = try holdingSession()
    session = record
    holding = nil
    return record
  }

  /// The session to go on with, or, while there is none, one that holds what is said until there is.
  private func holdingSession() throws -> SessionRecord {
    if let record = session ?? holding { return record }
    let fresh = SessionRecord(
      id: context.environment.newID(), owner: owner, runtime: context.agents.provisionalRuntime(for: work.runsOn),
      instructions: "",
      startedAt: context.environment.now())
    try context.database.start(fresh)
    holding = fresh
    return fresh
  }

  private func mirror(_ messages: [Message], of session: SessionRecord) {
    Self.mirror(messages, of: session, in: home, context: context)
  }

  private func dropLive() async {
    let closing = live
    live = nil
    courseToolAccess = nil
    await closing?.close()
  }

  /// Shows what changed once the moment is over, together with whatever else changes until then.
  private func changedSoon() {
    guard showing == nil else { return }
    let wait = context.environment.wait
    showing = Task {
      await wait(Self.showEvery)
      await self.show()
    }
  }

  private func show() async {
    showing = nil
    await changed(ended: false)
  }

  private func changed(ended: Bool) async {
    switch owner {
    case .conversation(let conversation):
      await context.follower.follow(
        ended ? [.conversation(conversation), .turnEnded(conversation)] : [.conversation(conversation)])
    case .review:
      await context.follower.follow([.review])
    case .panel, .run:
      break
    }
  }
}
