import Foundation
import LociAgents
import LociHost
import LociModel

actor ManualAgent: AgentDriver {
  nonisolated let provider = Mentor.Provider.pi
  private(set) var opened: [SessionConfiguration] = []
  private(set) var sessions: [ManualSession] = []
  let openingFailure: AgentError?

  init(openingFailure: AgentError? = nil) {
    self.openingFailure = openingFailure
  }

  func open(_ configuration: SessionConfiguration) async throws(AgentError) -> any AgentSession {
    opened.append(configuration)
    if let openingFailure { throw openingFailure }
    if configuration.resume != nil { throw .sessionNotFound }
    let session = ManualSession(number: sessions.count + 1)
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

  init(number: Int) {
    handle = SessionHandle(provider: .pi, value: "manual-\(number)")
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard output == nil else { throw .turnInProgress }
    prompts.append(text)
    let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    if text.contains("new mentor") {
      continuation.yield(.text("Ready."))
      continuation.yield(.ended(.completed))
      continuation.finish()
    } else {
      output = continuation
      continuation.yield(.text("Waiting"))
    }
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
  let environment = HostEnvironment(
    newID: { world.nextID() }, now: { TestWorld.instant }, defaultProvider: .pi, discard: .permanently,
    agents: { _ in agent })
  let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
  do {
    try await body(host, place, world, agent)
  } catch {
    await host.close()
    throw error
  }
  await host.close()
}
