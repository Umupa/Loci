import Foundation

actor CodexSession: AgentSession {
  nonisolated let handle: SessionHandle
  private let channel: CodexChannel
  private let clock: any Clock<Duration>
  private var running: (state: CodexTurnState, pipe: TurnPipe)?
  private var stopping = false
  private var closing = false
  private var generation = 0

  init(handle: SessionHandle, channel: CodexChannel, clock: any Clock<Duration>) {
    self.handle = handle
    self.channel = channel
    self.clock = clock
    Task { await self.listen() }
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard running == nil else { throw .turnInProgress }
    guard !closing else { throw .rejected("Session closed") }
    let pipe = TurnPipe()
    running = (CodexTurnState(), pipe)
    stopping = false
    generation += 1
    let sent = generation
    do throws(AgentError) {
      let accepted = try await channel.request(
        "turn/start",
        params: .object([
          "threadId": .string(handle.value),
          "input": .array([.object(["type": .string("text"), "text": .string(text)])]),
        ]), within: .seconds(45))
      if generation == sent, running != nil {
        guard let id = accepted["turn"]?["id"]?.string else { throw .rejected("turn/start") }
        running?.state.id = id
        if stopping { await stopTurn(id) }
      }
    } catch {
      if generation == sent { finish(.failed(error)) }
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
      await running?.pipe.finished.value
      return
    }
    stopping = true
    let request = Task {
      let id = running?.state.id
      await withdraw()
      guard !Task.isCancelled else { return }
      if let id { await stopTurn(id) }
    }
    await running?.pipe.finished.value
    request.cancel()
  }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    guard let reply = running?.state.answer(request, with: answer) else { return }
    do { try await channel.send(reply) } catch { finish(.failed(error)) }
  }

  func close() async {
    closing = true
    stopping = true
    await withdraw()
    await channel.connection.shutDown(patience: .seconds(3))
    await running?.pipe.finished.value
  }

  private func listen() async {
    for await record in channel.records { await receive(record) }
    let reason = await channel.connection.ended ?? .exited(code: -1, diagnostics: "")
    finish(stopping ? .interrupted : .failed(reason))
  }

  private func receive(_ record: CodexRecord) async {
    switch record {
    case .response: break
    case .notification(let method, let params):
      guard params["threadId"]?.string == handle.value else { return }
      if method == "turn/started" {
        running?.state.id = params["turn"]?["id"]?.string
      } else if method == "turn/completed" {
        let turn = params["turn"]
        if let active = running?.state.id, turn?["id"]?.string != active { return }
        switch turn?["status"]?.string {
        case "completed": finish(stopping ? .interrupted : .completed)
        case "interrupted": finish(.interrupted)
        case "failed": finish(.failed(.provider(turn?["error"]?["message"]?.string ?? "Codex turn failed")))
        default: finish(.failed(.rejected("turn/completed")))
        }
      } else {
        if let turn = params["turnId"]?.string, let active = running?.state.id, turn != active { return }
        for event in running?.state.receive(method, params) ?? [] { running?.pipe.yield(event) }
      }
    case .request(let id, let method, let params):
      let reply: JSONValue
      if let dialog = CodexDialog(id: id, method: method, params: params) {
        if running != nil, !stopping, params["threadId"]?.string == handle.value,
          params["turnId"]?.string == running?.state.id
        {
          if let event = running?.state.ask(dialog) { running?.pipe.yield(event) }
          return
        }
        reply = dialog.reply(to: .dismissed)
      } else {
        reply = .object([
          "id": id,
          "error": .object([
            "code": .number(-32601), "message": .string("Unsupported client request: \(method)"),
          ]),
        ])
        running?.pipe.yield(.notice(.message("Unsupported client request: \(method)")))
      }
      do { try await channel.send(reply) } catch { finish(.failed(error)) }
    }
  }

  private func stopTurn(_ id: String) async {
    let sent = generation
    do {
      _ = try await channel.request(
        "turn/interrupt",
        params: .object([
          "threadId": .string(handle.value), "turnId": .string(id),
        ]), within: .seconds(15))
    } catch {
      if generation == sent, !Task.isCancelled { forceInterrupt() }
    }
  }

  private func withdraw() async {
    let withdrawn = running?.state.withdraw() ?? []
    for (reply, event) in withdrawn {
      running?.pipe.yield(event)
      do { try await channel.send(reply) } catch { finish(.failed(error)) }
    }
  }

  private func forceInterrupt() {
    guard running != nil else { return }
    closing = true
    channel.connection.terminate()
    finish(.interrupted)
  }

  private func finish(_ end: TurnEnd) {
    guard let turn = running else { return }
    for (_, event) in running?.state.withdraw() ?? [] { turn.pipe.yield(event) }
    turn.pipe.end(end)
    running = nil
  }
}
