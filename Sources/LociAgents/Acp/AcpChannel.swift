import Foundation

/// The pipe to one running ACP agent: pairs each request with its response and hands on everything else.
actor AcpChannel {
  /// Requests and notifications from the agent. Finishes when the program has ended.
  nonisolated let records: AsyncStream<AcpRecord>

  private let program: RunningProgram
  private let clock: any Clock<Duration>
  private let incoming: AsyncStream<AcpRecord>.Continuation
  private var framer = LineFramer()
  private var sent = 0
  private var waiting: [Int: CheckedContinuation<Result<JSONValue, AgentError>, Never>] = [:]
  private var diagnostics = Data()
  private var open = (output: true, diagnostics: true)
  private var status: Int32?
  private var acceptingUpdates = false
  private var whenEnded: [CheckedContinuation<Void, Never>] = []
  /// Why the channel is over, once it is.
  private(set) var ended: AgentError?

  init(program: RunningProgram, clock: any Clock<Duration>) {
    self.program = program
    self.clock = clock
    (records, incoming) = AsyncStream.makeStream(of: AcpRecord.self)
    Task { await self.read() }
    Task { await self.readDiagnostics() }
    Task { await self.watchExit() }
  }

  /// Starts forwarding session updates after setup and its history replay have finished.
  func acceptUpdates() {
    acceptingUpdates = true
  }

  /// Sends a request and waits for the response, for at most `limit` when one is given.
  func request(_ method: String, _ params: JSONValue, within limit: Duration?) async throws(AgentError) -> JSONValue {
    if let ended { throw ended }
    sent += 1
    let id = sent
    let deadline = limit.map { limit in
      Task { [clock] in
        do { try await clock.sleep(for: limit) } catch { return }
        self.resolve(id, .failure(.unresponsive(method)))
      }
    }
    let outcome = await withCheckedContinuation { continuation in
      waiting[id] = continuation
      try? program.write(AcpOutgoing.request(id: id, method: method, params: params))
    }
    deadline?.cancel()
    return try outcome.get()
  }

  func notify(_ method: String, _ params: JSONValue) {
    try? program.write(AcpOutgoing.notification(method: method, params: params))
  }

  func respond(to id: JSONValue, with result: JSONValue) {
    try? program.write(AcpOutgoing.result(id: id, result))
  }

  func refuse(_ id: JSONValue, method: String) {
    try? program.write(AcpOutgoing.methodNotFound(id: id, method))
  }

  nonisolated func terminate() {
    program.terminate()
  }

  /// Asks the agent to leave by closing its input, insists after `patience`, and returns once it has gone.
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
        guard let record = AcpRecord(line: line) else { continue }
        if case .response(let id, let outcome) = record {
          resolve(id, outcome)
        } else {
          if case .notification("session/update", _) = record, !acceptingUpdates { continue }
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

  /// A child of the agent can keep the pipes open after the agent itself is gone, so the pipes get a
  /// moment and no more.
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

  private func resolve(_ id: Int, _ outcome: Result<JSONValue, AgentError>) {
    waiting.removeValue(forKey: id)?.resume(returning: outcome)
  }
}
