import Foundation

/// The pipe to one running Claude Code: pairs each command with its response and hands on everything else.
actor ClaudeCodeChannel {
  /// Everything Claude Code says that is not a response to a command. Finishes when the program has ended.
  nonisolated let records: AsyncStream<ClaudeCodeRecord>

  private let program: RunningProgram
  private let clock: any Clock<Duration>
  private let incoming: AsyncStream<ClaudeCodeRecord>.Continuation
  private var framer = LineFramer()
  private var sent = 0
  private var waiting: [String: CheckedContinuation<Result<JSONValue, AgentError>, Never>] = [:]
  private var diagnostics = Data()
  private var open = (output: true, diagnostics: true)
  private var status: Int32?
  private var whenEnded: [CheckedContinuation<Void, Never>] = []
  /// Why the channel is over, once it is.
  private(set) var ended: AgentError?

  init(program: RunningProgram, clock: any Clock<Duration>) {
    self.program = program
    self.clock = clock
    (records, incoming) = AsyncStream.makeStream(of: ClaudeCodeRecord.self)
    Task { await self.read() }
    Task { await self.readDiagnostics() }
    Task { await self.watchExit() }
  }

  /// Sends a control command and waits for its response.
  func request(_ command: ClaudeCodeCommand, within limit: Duration) async throws(AgentError) -> JSONValue {
    if let ended { throw ended }
    sent += 1
    let id = "loci-\(sent)"
    let deadline = Task { [clock] in
      do { try await clock.sleep(for: limit) } catch { return }
      self.resolve(id, .failure(.unresponsive(command.name)))
    }
    let outcome = await withCheckedContinuation { continuation in
      waiting[id] = continuation
      do { try program.write(command.line(id: id)) } catch {
        resolve(id, .failure(.rejected(String(describing: error))))
      }
    }
    deadline.cancel()
    return try outcome.get()
  }

  /// Sends a record that has no control response.
  func send(_ command: ClaudeCodeCommand) throws(AgentError) {
    if let ended { throw ended }
    do { try program.write(command.line(id: "")) } catch { throw .rejected(String(describing: error)) }
  }

  nonisolated func terminate() {
    program.terminate()
  }

  /// Closes input, terminates after `patience`, and returns once the program has gone.
  func shutDown(patience: Duration) async {
    program.closeInput()
    let insist = Task { [clock, program] in
      do { try await clock.sleep(for: patience) } catch { return }
      program.terminate()
    }
    if ended == nil {
      await withCheckedContinuation { whenEnded.append($0) }
    }
    insist.cancel()
  }

  private func read() async {
    for await chunk in program.output {
      for line in framer.receive(chunk) {
        guard let record = ClaudeCodeRecord(line: line) else { continue }
        if case .response(let id, let outcome) = record {
          resolve(id, outcome)
        } else {
          incoming.yield(record)
        }
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

  /// A child process can keep the pipes open after the agent is gone, so the pipes get a moment and no more.
  private func watchExit() async {
    status = await program.exit()
    finishIfOver()
    try? await clock.sleep(for: .seconds(1))
    finish()
  }

  private func finishIfOver() {
    if status != nil, !open.output, !open.diagnostics { finish() }
  }

  private func finish() {
    guard ended == nil, let status else { return }
    let text = String(decoding: diagnostics, as: UTF8.self).plain.trimmingCharacters(in: .whitespacesAndNewlines)
    let error = AgentError.exited(code: status, diagnostics: text)
    ended = error
    for id in Array(waiting.keys) { resolve(id, .failure(error)) }
    incoming.finish()
    for continuation in whenEnded { continuation.resume() }
    whenEnded = []
  }

  private func resolve(_ id: String, _ outcome: Result<JSONValue, AgentError>) {
    waiting.removeValue(forKey: id)?.resume(returning: outcome)
  }
}
