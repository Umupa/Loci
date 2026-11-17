import Foundation

actor AcpSession: AgentSession {
  nonisolated let handle: SessionHandle

  private let channel: AcpChannel
  private let session: String
  private let window: Int?
  private let replyFailure: (@Sendable (String) -> String?)?
  private var running: (state: AcpTurnState, pipe: TurnPipe)?
  /// The caller asked the running turn, or the whole session, to stop.
  private var stopping = false
  private var whenIdle: [CheckedContinuation<Void, Never>] = []

  init(handle: SessionHandle, channel: AcpChannel, window: Int?, replyFailure: (@Sendable (String) -> String?)? = nil) {
    self.handle = handle
    self.session = handle.value
    self.channel = channel
    self.window = window
    self.replyFailure = replyFailure
    Task { await self.listen() }
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard running == nil else { throw .turnInProgress }
    if let ended = await channel.ended { throw ended }
    let pipe = TurnPipe()
    running = (AcpTurnState(replyFailure: replyFailure), pipe)
    stopping = false
    let params = JSONValue.object([
      "sessionId": .string(session),
      "prompt": .array([.object(["type": .string("text"), "text": .string(text)])]),
    ])
    Task { await self.prompt(params) }
    return pipe.turn
  }

  func interrupt() async {
    guard running != nil else { return }
    stopping = true
    await withdraw()
    await channel.notify("session/cancel", .object(["sessionId": .string(session)]))
    await idle()
  }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    guard let (id, result) = running?.state.answer(request, with: answer) else { return }
    await channel.respond(to: id, with: result)
  }

  func close() async {
    stopping = true
    await withdraw()
    await channel.shutDown(patience: .seconds(3))
    await idle()
  }

  /// A turn the agent cancels by itself, as Grok does when a tool is denied, has still completed.
  private func prompt(_ params: JSONValue) async {
    var end: TurnEnd
    do throws(AgentError) {
      let result = try await channel.request("session/prompt", params, within: nil)
      switch result["stopReason"]?.string {
      case "cancelled": end = stopping ? .interrupted : .completed
      case "refusal": end = .failed(.provider("The model refused to answer."))
      case "end_turn", nil: end = stopping ? .interrupted : .completed
      case let reason?: end = stopping ? .interrupted : .failed(.provider("The agent ended the turn (\(reason))."))
      }
    } catch {
      end = stopping ? .interrupted : .failed(Self.providerSide(error))
    }
    if end == .completed, let failure = running?.state.failure { end = .failed(failure) }
    if let used = running?.state.used {
      running?.pipe.yield(.context(ContextUsage(used: used, window: window)))
    }
    finish(end)
  }

  private func listen() async {
    for await record in channel.records {
      await receive(record)
    }
    let reason = await channel.ended ?? .exited(code: -1, diagnostics: "")
    finish(stopping ? .interrupted : .failed(reason))
  }

  private func receive(_ record: AcpRecord) async {
    switch record {
    case .notification("session/update", let params):
      for event in running?.state.receive(params) ?? [] { running?.pipe.yield(event) }
    case .request(let id, "session/request_permission", let params):
      if running != nil, !stopping, let event = running?.state.ask(id: id, params) {
        running?.pipe.yield(event)
      } else {
        await channel.respond(to: id, with: AcpTurnState.cancelled)
      }
    case .request(let id, let method, _):
      await channel.refuse(id, method: method)
    case .notification, .response:
      break
    }
  }

  private func withdraw() async {
    for (id, result, event) in running?.state.withdraw() ?? [] {
      await channel.respond(to: id, with: result)
      running?.pipe.yield(event)
    }
  }

  private func finish(_ end: TurnEnd) {
    guard let turn = running else { return }
    for (_, _, event) in running?.state.withdraw() ?? [] { turn.pipe.yield(event) }
    turn.pipe.end(end)
    running = nil
    for continuation in whenIdle { continuation.resume() }
    whenIdle = []
  }

  private func idle() async {
    guard running != nil else { return }
    await withCheckedContinuation { whenIdle.append($0) }
  }

  /// A refused prompt is the model's side failing, in the agent's own words.
  private static func providerSide(_ error: AgentError) -> AgentError {
    if case .rejected(let words) = error { return .provider(words) }
    return error
  }
}
