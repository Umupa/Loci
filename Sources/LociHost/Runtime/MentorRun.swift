import Foundation
import LociAgents
import LociModel
import LociStore

/// What every mentor's run shares: where things are kept, and how to say something changed.
struct RunContext: Sendable {
  let store: Store
  let database: StoreDatabase
  let environment: HostEnvironment
  let follower: Follower
}

/// What a mentor's conversation is about: its own course, or one item it reads along on.
enum RunScope: Hashable, Sendable {
  case course
  case item(EntityID)

  var item: EntityID? {
    if case .item(let item) = self { item } else { nil }
  }
}

/// One mentor's conversation in one scope: its agent session, the turn running now, and the messages
/// before it.
///
/// One turn runs at a time. A turn's messages are kept in memory while it runs and stored together when it
/// ends, so the stored conversation only ever grows by whole turns.
actor MentorRun {
  let mentor: EntityID
  let scope: RunScope
  let context: RunContext
  private var stored: [Message]
  private var conversation: ConversationRecord?
  private var session: (any AgentSession)?
  /// What the live session was opened for. A mentor whose agent, model or effort changed since gets a new
  /// session.
  private var openedFor: AgentChoice?
  private var turn: TurnRecord?
  /// What the agent last said about its context window. Kept only while the host runs.
  private var usage: ContextUsage?
  private var running: Task<Void, Never>?
  private var stopping = false
  /// A session just opened afresh on an item has not been told about the item yet.
  private var needsIntroduction = false

  init(mentor: EntityID, scope: RunScope = .course, context: RunContext) throws(HostError) {
    self.mentor = mentor
    self.scope = scope
    self.context = context
    _ = try attempt { try context.store.mentor(mentor) }
    stored = try attempt { try context.database.messages(of: mentor, on: scope.item) }
    conversation = try attempt { try context.database.latestConversation(of: mentor, on: scope.item) }
  }

  var isIdle: Bool { turn == nil }

  /// The turn running now, and what the agent last said about its context window.
  var live: (turn: LiveTurn?, context: ContextUsage?) { (turn?.live, usage) }

  func snapshot() -> Conversation {
    Conversation(mentor: mentor, messages: stored, turn: turn?.live, context: usage)
  }

  /// Starts a turn and returns at once; the turn goes on in the background. The agent is told `text`, which
  /// is the prompt's own text unless Loci adds to what the person wrote.
  func send(_ prompt: Prompt, saying text: String? = nil) async throws(HostError) {
    guard turn == nil else { throw .invalidRequest(Self.busy) }
    turn = TurnRecord(prompt: prompt, at: context.environment.now(), newID: context.environment.newID)
    stopping = false
    running = Task { await self.run(text ?? prompt.text) }
    await changed()
  }

  static let busy = "the mentor is still working on the last message"
  static let busyOnItem = "a mentor is still answering on this item"

  /// Stops the running turn and returns once it has ended.
  func stop() async {
    guard turn != nil else { return }
    stopping = true
    await session?.interrupt()
    await running?.value
  }

  /// Stops the turn and the agent. With `forget`, a course conversation is deleted too; what was said on an
  /// item stays with the item.
  func close(forget: Bool) async {
    await stop()
    await session?.close()
    session = nil
    if forget, scope == .course { try? context.database.deleteConversations(of: mentor) }
  }

  private func run(_ text: String) async {
    do throws(TurnFailure) {
      let session = try await openSession()
      if !stopping {
        let said = needsIntroduction ? introduction() + text : text
        needsIntroduction = false
        let started = try await TurnFailure.awaiting { () async throws(AgentError) in try await session.send(said) }
        if stopping { Task { await session.interrupt() } }
        for await event in started.events {
          switch event {
          case .permission(let request):
            await session.answer(request.id, with: Self.allowing(request))
            continue
          case .context(let reported):
            usage = reported
          default:
            turn?.apply(event, at: context.environment.now())
          }
          if case .ended(.failed(.exited)) = event { await dropSession() }
          await changed()
        }
      } else {
        turn?.apply(.ended(.interrupted), at: context.environment.now())
      }
    } catch {
      turn?.fail(error.reason, at: context.environment.now())
    }
    await finish()
  }

  /// Every mentor runs with full access, so a request the agent still makes is allowed.
  private static func allowing(_ request: PermissionRequest) -> PermissionAnswer {
    let roles: [PermissionRequest.Option.Role] = [.allow, .allowAlways]
    let option = roles.lazy.compactMap { role in request.options.first { $0.role == role } }.first
    return option.map { .chosen($0.id) } ?? .dismissed
  }

  private func finish() async {
    guard var turn else { return }
    await saveAnswer(of: &turn)
    do {
      try context.database.append(turn.messages, to: try storedConversation().id)
    } catch {
      await context.follower.hub.failed(String(describing: error))
    }
    stored += turn.messages
    self.turn = nil
    running = nil
    await changed()
  }

  /// The conversation to store a turn in. A turn whose agent never started still needs one.
  private func storedConversation() throws -> ConversationRecord {
    if let conversation { return conversation }
    let provider = (try? context.store.mentor(mentor).provider) ?? context.environment.defaultProvider
    let fresh = ConversationRecord(
      id: context.environment.newID(), mentor: mentor, item: scope.item, provider: provider, session: nil)
    try context.database.start(fresh, at: context.environment.now())
    conversation = fresh
    return fresh
  }

  private func dropSession() async {
    let closing = session
    session = nil
    openedFor = nil
    await closing?.close()
  }

  /// The mentor's agent, model or effort was changed. A session opened with other settings is closed now
  /// rather than at the next message; a running turn finishes as it began.
  func settingsChanged(to mentor: Mentor) async {
    guard let openedFor, openedFor != Self.choice(of: mentor), turn == nil else { return }
    await dropSession()
  }

  private static func choice(of mentor: Mentor) -> AgentChoice {
    AgentChoice(provider: mentor.provider, model: mentor.model, effort: mentor.effort)
  }

  /// The live session, resuming the conversation's own when the agent still has it.
  private func openSession() async throws(TurnFailure) -> any AgentSession {
    let store = context.store
    let mentor = try TurnFailure.from { () throws(HostError) in try attempt { try store.mentor(self.mentor) } }
    if let session, openedFor == Self.choice(of: mentor) { return session }
    await dropSession()
    guard let driver = await context.environment.agents(mentor.provider) else {
      throw TurnFailure(reason: "\(mentor.provider.rawValue) is not installed on this Mac.")
    }
    let soul = try TurnFailure.from { () throws(HostError) in try Soul.text(for: mentor) }
    let folder = try TurnFailure.from { () throws(HostError) in
      try attempt {
        try store.installSoul(soul, for: mentor.id)
        return try store.workingFolder(of: mentor.id)
      }
    }
    var configuration = SessionConfiguration(workingDirectory: folder, model: mentor.model, effort: mentor.effort)
    if let conversation, conversation.provider == mentor.provider, let id = conversation.session {
      configuration.resume = SessionHandle(provider: mentor.provider, value: id)
    }
    let opened: any AgentSession
    do {
      opened = try await driver.open(configuration)
    } catch {
      guard error == .sessionNotFound, configuration.resume != nil else {
        throw TurnFailure(reason: error.explanation)
      }
      configuration.resume = nil
      opened = try await TurnFailure.awaiting { () async throws(AgentError) in try await driver.open(configuration) }
    }
    try record(opened.handle, provider: mentor.provider)
    needsIntroduction = scope.item != nil && opened.handle != configuration.resume
    let now = try TurnFailure.from { () throws(HostError) in try attempt { try store.mentor(self.mentor) } }
    guard Self.choice(of: now) == Self.choice(of: mentor) else {
      await opened.close()
      return try await openSession()
    }
    session = opened
    openedFor = Self.choice(of: mentor)
    return opened
  }

  /// Keeps the conversation pointing at the session it is now in, starting a new conversation when the
  /// old session is gone or another provider runs the mentor.
  private func record(_ handle: SessionHandle, provider: Mentor.Provider) throws(TurnFailure) {
    let database = context.database
    if let conversation, conversation.provider == provider, conversation.session == handle.value { return }
    if let conversation, conversation.provider == provider, conversation.session == nil {
      try TurnFailure.from { () throws(HostError) in
        try attempt { try database.bind(session: handle.value, to: conversation.id) }
      }
      self.conversation = ConversationRecord(
        id: conversation.id, mentor: mentor, item: scope.item, provider: provider, session: handle.value)
      return
    }
    let fresh = ConversationRecord(
      id: context.environment.newID(), mentor: mentor, item: scope.item, provider: provider, session: handle.value)
    let now = context.environment.now()
    try TurnFailure.from { () throws(HostError) in try attempt { try database.start(fresh, at: now) } }
    conversation = fresh
  }

  private func changed() async {
    switch scope {
    case .course: await context.follower.follow([.conversation(mentor)])
    case .item(let item): await context.follower.follow([.itemConversation(item)])
    }
  }
}

/// Why a turn could not run, in words for the person.
struct TurnFailure: Error {
  let reason: String

  static func from<Value>(_ body: () throws(HostError) -> Value) throws(TurnFailure) -> Value {
    do {
      return try body()
    } catch {
      throw TurnFailure(reason: String(describing: error))
    }
  }

  static func awaiting<Value>(_ body: () async throws(AgentError) -> Value) async throws(TurnFailure) -> Value {
    do {
      return try await body()
    } catch {
      throw TurnFailure(reason: error.explanation)
    }
  }
}
