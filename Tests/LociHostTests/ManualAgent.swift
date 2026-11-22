import Foundation
import LociAgents
import LociHost
import LociModel

actor ManualAgent: AgentDriver {
  nonisolated let provider: Provider
  private(set) var opened: [SessionConfiguration] = []
  private(set) var sessions: [ManualSession] = []
  let openingFailure: AgentError?
  /// How many more sessions open at once; the ones after wait for `letOpen()`.
  private var opensFreely: Int
  private var held: [CheckedContinuation<Void, Never>] = []

  init(openingFailure: AgentError? = nil, opensFreely: Int = .max, provider: Provider = .pi) {
    self.provider = provider
    self.openingFailure = openingFailure
    self.opensFreely = opensFreely
  }

  var waitingToOpen: Int { held.count }

  func letOpen() {
    for opening in held { opening.resume() }
    held = []
  }

  func openFreely() {
    opensFreely = .max
    letOpen()
  }

  func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    if opensFreely > 0 {
      opensFreely -= 1
    } else {
      await withCheckedContinuation { held.append($0) }
    }
    opened.append(configuration)
    if let openingFailure { throw openingFailure }
    if configuration.resume != nil { throw .sessionNotFound }
    let session = ManualSession(number: sessions.count + 1, provider: provider)
    sessions.append(session)
    return session
  }
}

actor ManualSession: AgentSession {
  nonisolated let handle: SessionHandle
  private var output: AsyncStream<AgentEvent>.Continuation?
  private(set) var prompts: [String] = []
  private(set) var answers: [PermissionAnswer] = []
  private(set) var closed = false

  init(number: Int, provider: Provider = .pi) {
    handle = SessionHandle(provider: provider, value: "manual-\(number)")
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard output == nil else { throw .turnInProgress }
    prompts.append(text)
    let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    output = continuation
    continuation.yield(.text("Waiting"))
    return Turn(events: stream)
  }

  func emit(_ event: AgentEvent) {
    output?.yield(event)
  }

  func finish(_ end: TurnEnd = .completed) {
    output?.yield(.ended(end))
    output?.finish()
    output = nil
  }

  func interrupt() async { finish(.interrupted) }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    answers.append(answer)
  }

  func close() async {
    closed = true
    finish(.interrupted)
  }
}

func withManualHost(
  agent: ManualAgent = ManualAgent(),
  _ body: (LocalHost, Place, TestWorld, ManualAgent) async throws -> Void
) async throws {
  let place = Place()
  defer { place.remove() }
  let world = TestWorld()
  let environment = world.environment(running: { _ in agent })
  let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
  do {
    try await body(host, place, world, agent)
  } catch {
    await host.close()
    throw error
  }
  await host.close()
}
