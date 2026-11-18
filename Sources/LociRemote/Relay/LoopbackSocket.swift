/// One end of an in-process WebSocket. What one end sends, the other receives, in order.
actor LoopbackSocket: WebSocket {
  private let inbox = Mailbox<SocketMessage>()
  private var peer: LoopbackSocket?
  private var closedWith: Int?
  private let answersPings: @Sendable () async -> Bool
  private let received: @Sendable (SocketMessage) async -> Void

  /// `received` runs after each message this end hands to its reader, for a relay that acknowledges
  /// bytes once the client has taken them.
  init(
    answersPings: @escaping @Sendable () async -> Bool = { true },
    received: @escaping @Sendable (SocketMessage) async -> Void = { _ in }
  ) {
    self.answersPings = answersPings
    self.received = received
  }

  static func connect(_ one: LoopbackSocket, _ other: LoopbackSocket) async {
    await one.attach(other)
    await other.attach(one)
  }

  private func attach(_ peer: LoopbackSocket) {
    self.peer = peer
  }

  func send(_ message: SocketMessage) async throws(SocketError) {
    if let closedWith { throw .closed(code: closedWith) }
    await peer?.deliver(message)
  }

  func receive() async throws(SocketError) -> SocketMessage {
    guard let message = await inbox.take() else { throw .closed(code: closedWith ?? 1006) }
    await received(message)
    return message
  }

  func close(code: Int) async {
    guard closedWith == nil else { return }
    closedWith = code
    await inbox.finish()
    await peer?.closedByPeer(code: code)
  }

  func ping() async throws(SocketError) {
    if let closedWith { throw .closed(code: closedWith) }
    guard await answersPings() else {
      try? await Task.sleep(for: .seconds(3600))
      throw .timedOut
    }
  }

  private func deliver(_ message: SocketMessage) async {
    await inbox.put(message)
  }

  private func closedByPeer(code: Int) async {
    guard closedWith == nil else { return }
    closedWith = code
    await inbox.finish()
  }
}
