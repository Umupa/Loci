/// The only way a driver hands out a turn's events: once ended, nothing more gets through.
struct TurnPipe: Sendable {
  let finished: Task<Void, Never>
  private let completion: AsyncStream<Void>.Continuation
  let turn: Turn
  private let continuation: AsyncStream<AgentEvent>.Continuation

  init() {
    let (events, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    self.turn = Turn(events: events)
    self.continuation = continuation
    let (ended, completion) = AsyncStream.makeStream(of: Void.self)
    self.completion = completion
    finished = Task { for await _ in ended {} }
  }

  func yield(_ event: AgentEvent) {
    if case .ended = event {
      continuation.yield(event)
      continuation.finish()
      completion.finish()
    } else {
      continuation.yield(event)
    }
  }

  func end(_ end: TurnEnd) {
    yield(.ended(end))
  }
}
