import Foundation
import LociModel

actor PiSession: AgentSession {
  nonisolated let handle: SessionHandle

  private let channel: PiChannel
  private let clock: any Clock<Duration>
  private let window: Int?
  private var running: (state: PiTurnState, pipe: TurnPipe)?
  /// The caller asked the running turn, or the whole session, to stop.
  private var stopping = false
  private var closed = false

  init(handle: SessionHandle, channel: PiChannel, window: Int?, clock: any Clock<Duration>) {
    self.handle = handle
    self.channel = channel
    self.clock = clock
    self.window = window
    Task { await self.listen() }
  }

  func send(_ text: String) async throws(AgentError) -> Turn {
    guard !closed else { throw .rejected("Session closed") }
    guard running == nil else { throw .turnInProgress }
    let pipe = TurnPipe()
    running = (PiTurnState(), pipe)
    stopping = false
    do throws(AgentError) {
      let accepted = try await channel.request(.prompt(text), within: .seconds(15))
      if accepted["disposition"]?.string == "handled" || accepted["agentInvoked"]?.bool == false {
        finish(.completed)
      }
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
      await running?.pipe.finished.value
      return
    }
    stopping = true
    let request = Task {
      await withdraw()
      guard !Task.isCancelled else { return }
      do { _ = try await channel.request(.abort, within: .seconds(30)) } catch {
        if !Task.isCancelled { forceInterrupt() }
      }
    }
    await running?.pipe.finished.value
    request.cancel()
  }

  func answer(_ request: PermissionRequest.ID, with answer: PermissionAnswer) async {
    guard let reply = running?.state.answer(request, with: answer) else { return }
    do throws(AgentError) { try await channel.send(reply) } catch { finish(.failed(error)) }
  }

  func close() async {
    stopping = true
    await channel.connection.shutDown(patience: .seconds(3))
    await running?.pipe.finished.value
  }

  private func listen() async {
    for await record in channel.records {
      await receive(record)
    }
    let reason = await channel.connection.ended ?? .exited(code: -1, diagnostics: "")
    finish(stopping ? .interrupted : .failed(reason))
  }

  private func receive(_ record: PiRecord) async {
    switch record {
    case .event(.settled(let aborted)):
      await settle(aborted: aborted)
    case .event(.promptResult(let invoked, let aborted, let failure)):
      if let failure { _ = running?.state.receive(.replyFailed(failure)) }
      if aborted { stopping = true }
      if !invoked { await settle(aborted: aborted) }
    case .dialogClosed(let id):
      if running?.state.cancelDialog(id) == true { running?.pipe.yield(.permissionClosed(.init(id))) }
    case .event(let event):
      for event in running?.state.receive(event) ?? [] { running?.pipe.yield(event) }
    case .dialog(let dialog):
      if running != nil, !stopping, let event = running?.state.ask(dialog) {
        running?.pipe.yield(event)
      } else {
        do throws(AgentError) { try await channel.send(dialog.reply(to: .dismissed)) } catch { finish(.failed(error)) }
      }
    case .unanswerable(let id, let title):
      do throws(AgentError) { try await channel.send(.reply(dialog: id, .cancelled)) } catch { finish(.failed(error)) }
      if !title.isEmpty { running?.pipe.yield(.notice(.message(title))) }
    case .notice(let notice):
      running?.pipe.yield(.notice(notice))
    case .response:
      break
    }
  }

  private func settle(aborted: Bool) async {
    guard let end = running?.state.end(interrupted: aborted || stopping) else { return }
    if let stats = try? await channel.request(.getSessionStats, within: .seconds(4)),
      let used = stats["contextUsage"]?["tokens"]?.int
    {
      running?.pipe.yield(
        .context(ContextUsage(used: used, window: stats["contextUsage"]?["contextWindow"]?.int ?? window)))
    }
    finish(end)
  }

  private func withdraw() async {
    for (reply, event) in running?.state.withdraw() ?? [] {
      do throws(AgentError) { try await channel.send(reply) } catch { finish(.failed(error)) }
      running?.pipe.yield(event)
    }
  }

  private func forceInterrupt() {
    guard running != nil else { return }
    closed = true
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
