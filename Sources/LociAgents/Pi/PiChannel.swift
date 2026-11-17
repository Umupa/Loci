import Foundation

/// The pipe to one running Pi: pairs each command with its response and hands on everything else.
actor PiChannel {
  /// Everything Pi says that is not a response to a command. Finishes when the program has ended.
  nonisolated let records: AsyncStream<PiRecord>

  private let program: RunningProgram
  private let clock: any Clock<Duration>
  private let incoming: AsyncStream<PiRecord>.Continuation
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
    (records, incoming) = AsyncStream.makeStream(of: PiRecord.self)
    Task { await self.read() }
    Task { await self.readDiagnostics() }
    Task { await self.watchExit() }
  }

  /// Sends a command and waits for Pi's response to it.
  func request(_ command: PiCommand, within limit: Duration) async throws(AgentError) -> JSONValue {
    if let ended { throw ended }
    sent += 1
    let id = "loci-\(sent)"
    let deadline = Task { [clock] in
      do { try await clock.sleep(for: limit) } catch { return }
      self.resolve(id, .failure(.unresponsive(command.name)))
    }
    let outcome = await withCheckedContinuation { continuation in
      waiting[id] = continuation
      try? program.write(command.record(id: id).line)
    }
    deadline.cancel()
    return try outcome.get()
  }

  /// Sends a record Pi does not respond to.
  func send(_ command: PiCommand) {
    try? program.write(command.record(id: "").line)
  }

  nonisolated func terminate() {
    program.terminate()
  }

  /// Asks Pi to leave by closing its input, insists after `patience`, and returns once it has gone.
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
        guard let record = PiRecord(line: line) else { continue }
        if case .response(let id, _, let outcome) = record {
          if let id { resolve(id, outcome) }
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

  /// A child of Pi can keep the pipes open after Pi itself is gone, so the pipes get a moment and no more.
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
