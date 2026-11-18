/// One client's socket inside the agent's connection to the relay, addressed by the relay's stream id.
actor BridgedSocket: MessageSocket {
  private let id: String
  private let agent: RelayAgent
  private let inbox = Mailbox<SocketMessage>()
  private var closedWith: Int?

  init(id: String, agent: RelayAgent) {
    self.id = id
    self.agent = agent
  }

  func send(_ message: SocketMessage) async throws(SocketError) {
    if let closedWith { throw .closed(code: closedWith) }
    try await agent.send(message, on: id)
  }

  func receive() async throws(SocketError) -> SocketMessage {
    if let message = await inbox.take() { return message }
    throw .closed(code: closedWith ?? 1006)
  }

  func close(code: Int) async {
    await agent.close(id, code: code)
  }

  func deliver(_ message: SocketMessage) async {
    await inbox.put(message)
  }

  func finish(code: Int) async {
    closedWith = closedWith ?? code
    await inbox.finish()
  }
}
