import Foundation

/// Owns one program's line transport, pending requests, diagnostics, and shutdown.
actor ProgramConnection {
  private let program: RunningProgram
  private let clock: any Clock<Duration>
  private var waiting: [String: CheckedContinuation<Result<JSONValue, AgentError>, Never>] = [:]
  private var diagnostics = Data()
  private var open = (output: true, diagnostics: true)
  private var status: Int32?
  private var whenEnded: [CheckedContinuation<AgentError, Never>] = []
  private(set) var ended: AgentError?

  init(program: RunningProgram, clock: any Clock<Duration>) {
    self.program = program
    self.clock = clock
  }

  /// Routes each complete line before ending, allowing responses just before exit to resolve.
  func listen(receive: @escaping @Sendable (Data) async -> Void) async -> AgentError {
    if let ended { return ended }
    let output = Task { await read(receive: receive) }
    let diagnostics = Task { await readDiagnostics() }
    let exit = Task { await watchExit() }
    defer {
      output.cancel()
      diagnostics.cancel()
      exit.cancel()
    }
    return await end()
  }

  func request(_ id: String, data: Data, operation: String, within limit: Duration) async throws(AgentError)
    -> JSONValue
  {
    if let ended { throw ended }
    let deadline = Task { [clock] in
      do { try await clock.sleep(for: limit) } catch { return }
      resolve(id, .failure(.unresponsive(operation)))
    }
    let outcome = await withCheckedContinuation { continuation in
      waiting[id] = continuation
      do throws(AgentError) { try send(data) } catch { resolve(id, .failure(error)) }
    }
    deadline.cancel()
    return try outcome.get()
  }

  func resolve(_ id: String, _ outcome: Result<JSONValue, AgentError>) {
    waiting.removeValue(forKey: id)?.resume(returning: outcome)
  }

  func send(_ data: Data) throws(AgentError) {
    if let ended { throw ended }
    do { try program.write(data) } catch {
      let failure = AgentError.rejected(error.localizedDescription)
      finish(failure)
      program.terminate()
      throw failure
    }
  }

  nonisolated func terminate() {
    program.terminate()
  }

  /// Closes input, terminates after `patience`, and returns once the connection has ended.
  func shutDown(patience: Duration) async {
    program.closeInput()
    let insist = Task { [clock, program] in
      do { try await clock.sleep(for: patience) } catch { return }
      program.terminate()
    }
    _ = await end()
    insist.cancel()
  }

  private func end() async -> AgentError {
    if let ended { return ended }
    return await withCheckedContinuation { whenEnded.append($0) }
  }

  private func read(receive: @Sendable (Data) async -> Void) async {
    var framer = LineFramer()
    for await chunk in program.output {
      for line in framer.receive(chunk) {
        guard ended == nil else { return }
        await receive(line)
      }
    }
    open.output = false
    finishIfOver()
  }

  private func readDiagnostics() async {
    for await chunk in program.diagnostics {
      diagnostics = Data((diagnostics + chunk).suffix(2000))
    }
    open.diagnostics = false
    finishIfOver()
  }

  private func watchExit() async {
    status = await program.exit()
    finishIfOver()
    do { try await clock.sleep(for: .seconds(1)) } catch { return }
    finishExit()
  }

  private func finishIfOver() {
    if !open.output, !open.diagnostics { finishExit() }
  }

  private func finishExit() {
    guard let status else { return }
    let text = String(decoding: diagnostics, as: UTF8.self).plain.trimmingCharacters(in: .whitespacesAndNewlines)
    finish(.exited(code: status, diagnostics: text))
  }

  private func finish(_ error: AgentError) {
    guard ended == nil else { return }
    ended = error
    for id in Array(waiting.keys) { resolve(id, .failure(error)) }
    for continuation in whenEnded { continuation.resume(returning: error) }
    whenEnded = []
  }
}
