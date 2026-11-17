import Foundation
import LociModel

actor AcpSession: AgentSession {
  nonisolated let handle: SessionHandle

  private let channel: AcpChannel
  private let session: String
  private let window: Int?
  private let permission: Mentor.Permission
  private var running: (state: AcpTurnState, pipe: TurnPipe)?
  /// The caller asked the running turn, or the whole session, to stop.
  private var stopping = false
  private var whenIdle: [CheckedContinuation<Void, Never>] = []

  init(handle: SessionHandle, channel: AcpChannel, window: Int?, permission: Mentor.Permission) {
    self.handle = handle
    self.session = handle.value
    self.channel = channel
    self.window = window
    self.permission = permission
    Task { await self.listen() }
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard running == nil else { throw .turnInProgress }
    if let ended = await channel.ended { throw ended }
    let pipe = TurnPipe()
    running = (AcpTurnState(), pipe)
    stopping = false
    let params = JSONValue.object([
      "sessionId": .string(session),
      "prompt": .array([.object(["type": .string("text"), "text": .string(text)])]),
    ])
    do {
      try await channel.prompt(params)
    } catch {
      finish(.failed(error))
      throw error
    }
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
  private func settle(_ outcome: Result<JSONValue, AgentError>) {
    let end: TurnEnd
    switch outcome {
    case .success(let result):
      switch result["stopReason"]?.string {
      case "cancelled": end = stopping ? .interrupted : .completed
      case "refusal": end = .failed(.provider("The model refused to answer."))
      default: end = stopping ? .interrupted : .completed
      }
    case .failure(let error):
      end = stopping ? .interrupted : .failed(Self.providerSide(error))
    }
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
      guard params["sessionId"]?.string == session else { return }
      for event in running?.state.receive(params) ?? [] { running?.pipe.yield(event) }
    case .request(let id, "session/request_permission", let params):
      if params["sessionId"]?.string == session, running != nil, !stopping,
        let event = running?.state.ask(id: id, params)
      {
        if permission == .full, case .permission(let request) = event,
          let allow = request.options.first(where: { $0.role == .allowAlways })
            ?? request.options.first(where: { $0.role == .allow })
        {
          await answer(request.id, with: .chosen(allow.id))
        } else {
          running?.pipe.yield(event)
        }
      } else {
        await channel.respond(to: id, with: AcpTurnState.cancelled)
      }
    case .request(let id, let method, _):
      await channel.refuse(id, method: method)
    case .promptFinished(let result):
      settle(result)
    case .notification, .response:
      break
    }
  }

  private func withdraw() async {
    for (id, result, event) in running?.state.withdraw() ?? [] {
      running?.pipe.yield(event)
      await channel.respond(to: id, with: result)
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
