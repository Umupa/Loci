import Foundation

/// alma-relay's agent and client protocol, in this process, for running two Macs in one process. It
/// keeps what the real relay keeps (token hashes, never tokens), negotiates protocols 1 to 3,
/// acknowledges a client's bytes once the client has read them, displaces an agent registered twice with
/// close code 4000, and records every payload it forwards.
public actor LoopbackRelay: SocketDialer {
  private let proto: Int
  private let window: Int
  private let registrationKey: String?
  private var agents: [String: Agent] = [:]
  private var nextStream = 0
  private var answersPings = true
  /// Every payload forwarded between agents and clients, in order.
  public private(set) var traffic: [Data] = []
  private var clientDials: [String: Int] = [:]
  private var awaitingRegistration: [String: [CheckedContinuation<Void, Never>]] = [:]

  public static let address = URL(string: "ws://loopback.relay") ?? URL(filePath: "/")

  public init(proto: Int = 3, window: Int = 1 << 20, registrationKey: String? = nil) {
    self.proto = proto
    self.window = window
    self.registrationKey = registrationKey
  }

  public nonisolated var relay: Relay { Relay(address: Self.address, registrationKey: registrationKey) }

  /// Stops answering pings and forwarding anything, as a relay that went silent without closing.
  public func fallSilent() {
    answersPings = false
  }

  /// Closes every agent and client socket, as a relay that restarted.
  public func restart() async {
    answersPings = true
    for hash in agents.keys { await drop(hash, code: 1012) }
  }

  public var registeredCount: Int { agents.count }

  /// Returns once a Mac with this route token is registered.
  public func registration(of token: String) async {
    let hash = Relay.tokenHash(of: token)
    guard agents[hash] == nil else { return }
    await withCheckedContinuation { awaitingRegistration[hash, default: []].append($0) }
  }

  /// How many sockets clients opened to the Mac with this route token.
  public func clientDials(to token: String) -> Int {
    clientDials[Relay.tokenHash(of: token)] ?? 0
  }

  public func dial(_ url: URL) async throws(SocketError) -> any WebSocket {
    let path = url.path(percentEncoded: false)
    if path == "/agent" {
      let (outside, inside) = await pair()
      Task { await self.serveAgent(inside) }
      return outside
    }
    let parts = path.split(separator: "/", maxSplits: 2).map(String.init)
    let hash = parts.count >= 2 ? Relay.tokenHash(of: parts[1]) : ""
    guard parts.first == "c", let agent = agents[hash] else { throw .notOnRelay }
    clientDials[hash, default: 0] += 1
    nextStream += 1
    let id = "w\(nextStream)"
    let (client, bridge) = await pair(acknowledging: id, to: agent)
    agents[hash]?.bridges[id] = Bridge(socket: bridge)
    let rest = parts.count == 3 ? "/" + parts[2] : "/"
    try? await agent.socket.send(AgentFrame.socketOpen(id: id, path: rest).encoded(proto: agent.proto))
    Task { await self.forwardClient(bridge, id: id, hash: hash) }
    return client
  }

  private func pair(acknowledging id: String? = nil, to agent: Agent? = nil) async -> (LoopbackSocket, LoopbackSocket) {
    let pings: @Sendable () async -> Bool = { await self.answersPings }
    let outside = LoopbackSocket(answersPings: pings) { message in
      guard let id, let agent, agent.proto >= 3 else { return }
      try? await agent.socket.send(AgentFrame.ack(id: id, bytes: message.byteCount).encoded(proto: 1))
    }
    let inside = LoopbackSocket(answersPings: pings)
    await LoopbackSocket.connect(outside, inside)
    return (outside, inside)
  }

  private func serveAgent(_ socket: LoopbackSocket) async {
    let first = (try? await socket.receive()) ?? .text("")
    guard case .register(let hash, let key, let offered) = AgentFrame(first) else {
      await socket.close(code: 1002)
      return
    }
    guard key == registrationKey else {
      try? await socket.send(AgentFrame.error("bad key").encoded(proto: 1))
      await socket.close(code: 4003)
      return
    }
    if agents[hash] != nil { await drop(hash, code: 4000) }
    let agent = Agent(socket: socket, proto: min(offered, proto))
    agents[hash] = agent
    for waiter in awaitingRegistration.removeValue(forKey: hash) ?? [] { waiter.resume() }
    let window = agent.proto >= 3 ? window : nil
    try? await socket.send(AgentFrame.registered(proto: agent.proto, window: window).encoded(proto: 1))
    while let message = try? await socket.receive() {
      guard answersPings, let frame = AgentFrame(message) else { continue }
      await handle(frame, from: hash)
    }
    if agents[hash]?.socket === socket { await drop(hash, code: 1006) }
  }

  private func handle(_ frame: AgentFrame, from hash: String) async {
    guard let agent = agents[hash] else { return }
    switch frame {
    case .socketOpened(let id):
      guard let queued = agent.bridges[id]?.queued else { return }
      agents[hash]?.bridges[id]?.opened = true
      agents[hash]?.bridges[id]?.queued = []
      for message in queued { await forward(message, on: id, to: agent) }
    case .socketMessage(let id, let message):
      traffic.append(message.payload)
      try? await agent.bridges[id]?.socket.send(message)
    case .socketError(let id, _):
      await agents[hash]?.bridges.removeValue(forKey: id)?.socket.close(code: 1011)
    case .socketClose(let id, let code):
      await agents[hash]?.bridges.removeValue(forKey: id)?.socket.close(code: code ?? 1000)
    default:
      return
    }
  }

  private func forwardClient(_ bridge: LoopbackSocket, id: String, hash: String) async {
    while let message = try? await bridge.receive() {
      guard answersPings, let agent = agents[hash], let state = agent.bridges[id] else { continue }
      if state.opened {
        await forward(message, on: id, to: agent)
      } else {
        agents[hash]?.bridges[id]?.queued.append(message)
      }
    }
    guard let agent = agents[hash], agents[hash]?.bridges.removeValue(forKey: id) != nil else { return }
    try? await agent.socket.send(AgentFrame.socketClose(id: id, code: 1000).encoded(proto: agent.proto))
  }

  private func forward(_ message: SocketMessage, on id: String, to agent: Agent) async {
    traffic.append(message.payload)
    try? await agent.socket.send(AgentFrame.socketMessage(id: id, message).encoded(proto: agent.proto))
  }

  private func drop(_ hash: String, code: Int) async {
    guard let agent = agents.removeValue(forKey: hash) else { return }
    await agent.socket.close(code: code)
    for bridge in agent.bridges.values { await bridge.socket.close(code: 1012) }
  }

  private struct Agent: Sendable {
    let socket: LoopbackSocket
    let proto: Int
    var bridges: [String: Bridge] = [:]
  }

  private struct Bridge: Sendable {
    let socket: LoopbackSocket
    var opened = false
    var queued: [SocketMessage] = []
  }
}

extension SocketMessage {
  var payload: Data {
    switch self {
    case .text(let text): Data(text.utf8)
    case .binary(let data): data
    }
  }
}
