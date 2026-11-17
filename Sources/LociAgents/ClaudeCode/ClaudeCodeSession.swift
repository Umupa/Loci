import Foundation

actor ClaudeCodeSession: AgentSession {
  nonisolated let handle: SessionHandle
  private let channel: ClaudeCodeChannel
  private let clock: any Clock<Duration>
  private var running: (state: ClaudeCodeTurnState, pipe: TurnPipe)?
  private var stopping = false
  private var closed = false
  private var whenIdle: [CheckedContinuation<Void, Never>] = []

  init(handle: SessionHandle, channel: ClaudeCodeChannel, clock: any Clock<Duration>) {
    self.handle = handle
    self.channel = channel
    self.clock = clock
    Task { await self.listen() }
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard !closed else { throw .rejected("Session closed") }
    guard running == nil else { throw .turnInProgress }
    let pipe = TurnPipe()
    running = (ClaudeCodeTurnState(), pipe)
    stopping = false
    do throws(AgentError) {
      try await channel.send(.prompt(text))
    } catch {
      finish(.failed(error))
      throw error
    }
    return pipe.turn
  }

  func interrupt() async {
    guard running != nil else { return }
    let deadline = Task { [clock] in
      do { try await clock.sleep(for: .seconds(30)) } catch { return }
      guard !Task.isCancelled else { return }
      forceInterrupt()
    }
    defer { deadline.cancel() }
    if stopping {
      await idle()
      return
    }
    stopping = true
    let request = Task {
      await withdraw()
      guard !Task.isCancelled else { return }
      do { _ = try await channel.request(.control("interrupt"), within: .seconds(15)) } catch {
        if !Task.isCancelled { forceInterrupt() }
      }
    }
    await idle()
    request.cancel()
  }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    guard let reply = running?.state.answer(request, with: answer) else { return }
    do { try await channel.send(reply) } catch { finish(.failed(error)) }
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
      if case .message(let message) = record { await receive(message) }
    }
    let error = await channel.ended ?? .exited(code: -1, diagnostics: "")
    finish(stopping ? .interrupted : .failed(error))
  }

  private func receive(_ record: JSONValue) async {
    if record["type"]?.string == "control_request" {
      guard let dialog = ClaudeCodeDialog(record) else {
        if let id = record["request_id"]?.string {
          do { try await channel.send(.refuse(id)) } catch { finish(.failed(error)) }
        }
        return
      }
      if running != nil, !stopping, !closed {
        if let event = running?.state.ask(dialog) { running?.pipe.yield(event) }
      } else {
        try? await channel.send(dialog.reply(to: .dismissed))
      }
      return
    }
    for event in running?.state.receive(record) ?? [] { running?.pipe.yield(event) }
    if record["type"]?.string == "result", record["parent_tool_use_id"]?.string == nil,
      let end = running?.state.end(record, interrupted: stopping)
    {
      finish(end)
    }
  }

  private func withdraw() async {
    for (reply, event) in running?.state.withdraw() ?? [] {
      try? await channel.send(reply)
      running?.pipe.yield(event)
    }
  }

  private func forceInterrupt() {
    guard running != nil else { return }
    closed = true
    channel.terminate()
    finish(.interrupted)
  }

  private func finish(_ end: TurnEnd) {
    guard let turn = running else { return }
    for (_, event) in running?.state.withdraw() ?? [] { turn.pipe.yield(event) }
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
