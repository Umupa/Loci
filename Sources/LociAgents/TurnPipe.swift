/// The only way a driver hands out a turn's events: once ended, nothing more gets through.
struct TurnPipe: Sendable {
  let turn: Turn
  private let continuation: AsyncStream<AgentEvent>.Continuation

  init() {
    let (events, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    self.turn = Turn(events: events)
    self.continuation = continuation
  }

  func yield(_ event: AgentEvent) {
    if case .ended = event {
      continuation.yield(event)
      continuation.finish()
    } else {
      continuation.yield(event)
    }
  }

  func end(_ end: TurnEnd) {
    yield(.ended(end))
  }
}
