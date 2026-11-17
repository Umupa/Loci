import Foundation

actor OpenCodeSession: AgentSession {
  nonisolated let handle: SessionHandle

  private let channel: OpenCodeChannel
  private let clock: any Clock<Duration>
  private var running: (state: OpenCodeTurnState, pipe: TurnPipe)?
  private var stopping = false
  private var closed = false
  private var whenIdle: [CheckedContinuation<Void, Never>] = []

  init(handle: SessionHandle, channel: OpenCodeChannel, clock: any Clock<Duration>) {
    self.handle = handle
    self.channel = channel
    self.clock = clock
    Task { await self.listen() }
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard !closed else { throw .rejected("OpenCode session is closed") }
    guard running == nil else { throw .turnInProgress }
    let pipe = TurnPipe()
    running = (OpenCodeTurnState(), pipe)
    stopping = false
    do {
      try await channel.prompt(session: handle.value, text: text)
    } catch {
      finish(.failed(error))
      throw error
    }
    return pipe.turn
  }

  func interrupt() async {
    guard running != nil else { return }
    stopping = true
    let insist = Task { [clock, channel] in
      do { try await clock.sleep(for: .seconds(30)) } catch { return }
      channel.terminate()
    }
    do {
      try await channel.notify("session/cancel", session: handle.value)
      await withdraw()
    } catch {
      channel.terminate()
    }
    await idle()
    insist.cancel()
  }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    guard let dialog = running?.state.answer(request) else { return }
    do { try await channel.reply(dialog.id, result: dialog.reply(to: answer)) } catch {
      channel.terminate()
      finish(.failed(error))
    }
  }

  func close() async {
    closed = true
    stopping = true
    await withdraw()
    await channel.shutDown(patience: .seconds(3))
    await idle()
  }

  private func listen() async {
    for await record in channel.records {
      switch record {
      case .update(let session, let update):
        guard session == handle.value else { continue }
        for event in running?.state.receive(update) ?? [] { running?.pipe.yield(event) }
      case .request(let id, let method, let params):
        if method == "session/request_permission", let dialog = OpenCodeDialog(id: id, params: params) {
          if params["sessionId"]?.string == handle.value, running != nil, !stopping,
            let event = running?.state.ask(dialog)
          {
            running?.pipe.yield(event)
          } else {
            try? await channel.reply(id, result: dialog.reply(to: .dismissed))
          }
        } else {
          try? await channel.unsupported(id)
        }
      case .settled(let result):
        switch result {
        case .success(let result):
          let reason = result["stopReason"]?.string
          if stopping || reason == "cancelled" {
            finish(.interrupted)
          } else if reason == "end_turn" {
            finish(.completed)
          } else {
            finish(.failed(.provider("OpenCode stopped: \(reason ?? "unknown")")))
          }
        case .failure(let error):
          if case .rejected(let message) = error {
            finish(stopping ? .interrupted : .failed(.provider(message)))
          } else {
            finish(stopping ? .interrupted : .failed(error))
          }
        }
      case .response:
        break
      }
    }
    let error = await channel.ended ?? .exited(code: -1, diagnostics: "")
    closed = true
    finish(stopping ? .interrupted : .failed(error))
  }

  private func withdraw() async {
    for dialog in running?.state.withdraw() ?? [] {
      running?.pipe.yield(.permissionClosed(dialog.request.id))
      try? await channel.reply(dialog.id, result: dialog.reply(to: .dismissed))
    }
  }

  private func finish(_ end: TurnEnd) {
    guard let turn = running else { return }
    for dialog in running?.state.withdraw() ?? [] { turn.pipe.yield(.permissionClosed(dialog.request.id)) }
    turn.pipe.end(end)
    running = nil
    for continuation in whenIdle { continuation.resume() }
    whenIdle = []
  }

  private func idle() async {
    guard running != nil else { return }
    await withCheckedContinuation { whenIdle.append($0) }
  }
}
