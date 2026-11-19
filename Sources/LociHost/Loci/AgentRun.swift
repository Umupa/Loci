import Foundation
import LociAgents
import LociModel
import LociStore
import os

/// What every run shares: where things are kept, how to say something changed, and the texts Loci is given.
struct AgentContext: Sendable {
  let store: Store
  let database: StoreDatabase
  let environment: HostEnvironment
  let follower: Follower
  let prompts: Prompts

  /// What Loci runs on now.
  var runtime: Runtime { ((try? store.settings()) ?? HostSettings()).runtime ?? environment.defaultRuntime }

  /// `AGENTS.md` as it should be now.
  func instructions() throws(HostError) -> String {
    try attempt { prompts.instructions(soul: try store.agentText(.soul), profile: try store.agentText(.profile)) }
  }
}

/// One owner's turns, a conversation's or a day's review, over the agent sessions underneath.
///
/// One turn runs at a time. A turn's prompt is stored as soon as it is sent; the rest is kept in memory while
/// the turn runs and stored together when it ends. A turn the app quit during is stored as stopped when the
/// conversation is next opened. Before each turn the run decides whether the session goes on or a new one
/// starts; the person sees one conversation either way.
actor AgentRun {
  let owner: SessionOwner
  let context: AgentContext
  private var stored: [Message]
  /// The session to go on with; `nil` when there is none, or the person started over.
  private var session: SessionRecord?
  /// Where a prompt is stored while there is no session to go on with, until the agent's session takes it.
  private var holding: SessionRecord?
  private var live: (any AgentSession)?
  private var wear = SessionRotation.Wear()
  private var turn: TurnRecord?
  private var running: Task<Void, Never>?
  private var stopping = false
  private var lastTurn: [Message] = []
  /// What the turn did since it was last shown, waiting to be shown with what comes after it.
  private var showing: Task<Void, Never>?

  /// How long what a turn does is held before it is shown, so a reply streaming a word at a time is
  /// shown a few words at a time.
  static let showEvery = Duration.milliseconds(50)

  init(owner: SessionOwner, context: AgentContext) throws(HostError) {
    self.owner = owner
    self.context = context
    var stored = try attempt { try context.database.messages(of: owner) }
    let session =
      stored.last?.body == .startedOver ? nil : try attempt { try context.database.latestSession(of: owner) }
    if let cut = stored.last, case .prompt = cut.body, let session {
      let stopped = Message(id: context.environment.newID(), at: cut.at, body: .ended(.interrupted))
      try attempt { try context.database.append([stopped], to: session.id) }
      Self.mirror([cut, stopped], of: session, context: context)
      stored.append(stopped)
    }
    self.stored = stored
    self.session = session
  }

  static let busy = "Loci is still answering the last message here"

  var isIdle: Bool { turn == nil }

  /// What was said, the turn running now, and how full the session's context window last was.
  var snapshot: (messages: [Message], turn: LiveTurn?, context: ContextUsage?) { (stored, turn?.live, wear.usage) }

  /// Starts a turn and returns at once; the turn goes on in the background. Loci is told `text`, which
  /// adds to what the person wrote when they asked about a passage.
  func send(_ prompt: Prompt, saying text: String) async throws(HostError) {
    guard turn == nil else { throw .invalidRequest(Self.busy) }
    let started = TurnRecord(prompt: prompt, at: context.environment.now(), newID: context.environment.newID)
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

  /// Every session runs with full access, so a request the agent still makes is allowed.
  private static func allowing(_ request: PermissionRequest) -> PermissionAnswer {
    let roles: [PermissionRequest.Option.Role] = [.allow, .allowAlways]
    let option = roles.lazy.compactMap { role in request.options.first { $0.role == role } }.first
    return option.map { .chosen($0.id) } ?? .dismissed
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
    }
    self.session = remembered
    var parts = [prefix]
    if opening != nil, case .item(let item) = conversation, let introduction = context.introduction(to: item) {
      parts.append(introduction)
    }
    if let opening, opening.carriesOver, let recap = Recap.of(stored) { parts.append(recap) }
    parts.append(text)
    return parts.joined()
  }

  /// The live session, or a new one when the session cannot go on. Gives why a new one was opened, or `nil`
  /// when the turn goes on in the session it had.
  private func openSession() async throws(TurnFailure) -> (any AgentSession, SessionRotation.Reason?) {
    let runtime = context.runtime
    let instructions = try TurnFailure.from { () throws(HostError) in try context.instructions() }
    let fingerprint = Fingerprint.of(instructions)
    var reason = SessionRotation.reason(
      current: session, startedOver: stored.last?.body == .startedOver, wear: wear, runtime: runtime,
      instructions: fingerprint)
    if reason == nil, let live { return (live, nil) }
    await dropLive()
    if reason == nil, session?.handle == nil { reason = .lost }
    guard let driver = await context.environment.agents(runtime.provider) else {
      throw TurnFailure(.unstarted(runtime.provider, await context.environment.unavailability(runtime.provider)))
    }
    let store = context.store
    try TurnFailure.from { () throws(HostError) in try attempt { try store.writeInstructions(instructions) } }
    var configuration = SessionConfiguration(
      workingDirectory: store.agentFolder, model: runtime.model, effort: runtime.effort,
      environment: owner.toolEnvironment)
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
    return (opened, reason)
  }

  private func finish() async {
    guard var turn else { return }
    if case .conversation = owner { await saveAnswer(of: &turn) }
    do {
      let record = try sessionForStoring()
      try context.database.append(Array(turn.messages.dropFirst()), to: record.id)
      mirror(turn.messages, of: record)
    } catch {
      await context.follower.hub.failed(String(describing: error))
    }
    stored += turn.messages
    lastTurn = turn.messages
    self.turn = nil
    running = nil
    await changed(ended: true)
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
      id: context.environment.newID(), owner: owner, runtime: context.runtime, instructions: "",
      startedAt: context.environment.now())
    try context.database.start(fresh)
    holding = fresh
    return fresh
  }

  private func mirror(_ messages: [Message], of session: SessionRecord) {
    Self.mirror(messages, of: session, context: context)
  }

  /// A copy that cannot be written loses nothing the app needs; it is logged and the turn stands.
  private static func mirror(_ messages: [Message], of session: SessionRecord, context: AgentContext) {
    do {
      try context.store.mirror(messages, of: session, in: context.environment.timeZone)
    } catch {
      Logger(subsystem: "Loci", category: "agent").error(
        "could not copy the conversation: \(String(describing: error), privacy: .public)")
    }
  }

  private func dropLive() async {
    let closing = live
    live = nil
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
    }
  }
}

extension SessionRecord {
  func with(sent: [String: String]) -> SessionRecord {
    SessionRecord(
      id: id, owner: owner, runtime: runtime, handle: handle, instructions: instructions, sent: sent,
      startedAt: startedAt)
  }
}

/// Why a turn could not run, as the conversation tells it.
struct TurnFailure: Error {
  let ending: TurnEnding

  init(_ ending: TurnEnding) {
    self.ending = ending
  }

  /// Opening the provider's agent failed: it would not start, or it started and then failed.
  init(starting provider: Provider, _ error: AgentError) {
    switch error {
    case .wouldNotStart: ending = .unstarted(provider, .wouldNotStart)
    case .cannotLaunch: ending = .unstarted(provider, .notInstalled)
    default: ending = .failed(error.explanation)
    }
  }

  static func from<Value>(_ body: () throws(HostError) -> Value) throws(TurnFailure) -> Value {
    do {
      return try body()
    } catch {
      throw TurnFailure(.failed(String(describing: error)))
    }
  }

  static func awaiting<Value>(_ body: () async throws(AgentError) -> Value) async throws(TurnFailure) -> Value {
    do {
      return try await body()
    } catch {
      throw TurnFailure(.failed(error.explanation))
    }
  }
}

extension SessionOwner {
  /// What the `loci` command is told about the session it runs in: which conversation it is.
  fileprivate var toolEnvironment: [String: String] {
    switch self {
    case .conversation(let conversation): [LocalCall.sessionVariable: conversation.tag]
    case .review: [:]
    }
  }
}
