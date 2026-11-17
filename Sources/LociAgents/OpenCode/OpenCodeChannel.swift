import Foundation

actor OpenCodeChannel {
  nonisolated let records: AsyncStream<OpenCodeRecord>

  private let program: RunningProgram
  private let clock: any Clock<Duration>
  private let incoming: AsyncStream<OpenCodeRecord>.Continuation
  private var framer = LineFramer()
  private var sent = 0
  private var waiting: [JSONValue: CheckedContinuation<Result<JSONValue, AgentError>, Never>] = [:]
  private var promptID: JSONValue?
  private var promptDeadline: Task<Void, Never>?
  private var forwarding = false
  private var diagnostics = Data()
  private var open = (output: true, diagnostics: true)
  private var status: Int32?
  private var whenEnded: [CheckedContinuation<Void, Never>] = []
  private(set) var ended: AgentError?

  init(program: RunningProgram, clock: any Clock<Duration>) {
    self.program = program
    self.clock = clock
    (records, incoming) = AsyncStream.makeStream(of: OpenCodeRecord.self)
    Task { await self.read() }
    Task { await self.readDiagnostics() }
    Task { await self.watchExit() }
  }

  func request(_ method: String, _ params: JSONValue, within limit: Duration = .seconds(45)) async throws(AgentError)
    -> JSONValue
  {
    if let ended { throw ended }
    let id = nextID()
    let deadline = Task { [clock] in
      do { try await clock.sleep(for: limit) } catch { return }
      self.resolve(id, .failure(.unresponsive(method)))
    }
    let outcome = await withCheckedContinuation { continuation in
      waiting[id] = continuation
      do throws(AgentError) {
        try write(.object(["jsonrpc": .string("2.0"), "id": id, "method": .string(method), "params": params]))
      } catch {
        resolve(id, .failure(error))
      }
    }
    deadline.cancel()
    return try outcome.get()
  }

  func prompt(session: String, text: String) throws(AgentError) {
    if let ended { throw ended }
    let id = nextID()
    promptID = id
    do {
      try write(
        .object([
          "jsonrpc": .string("2.0"), "id": id, "method": .string("session/prompt"),
          "params": .object([
            "sessionId": .string(session),
            "prompt": .array([.object(["type": .string("text"), "text": .string(text)])]),
          ]),
        ]))
    } catch {
      promptID = nil
      throw error
    }
    promptDeadline = Task { [clock] in
      do { try await clock.sleep(for: .seconds(1800)) } catch { return }
      if self.promptID == id { self.terminate() }
    }
  }

  func activate() { forwarding = true }

  func notify(_ method: String, session: String) throws(AgentError) {
    try write(
      .object([
        "jsonrpc": .string("2.0"), "method": .string(method), "params": .object(["sessionId": .string(session)]),
      ]))
  }

  func reply(_ id: JSONValue, result: JSONValue) throws(AgentError) {
    try write(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
  }

  func unsupported(_ id: JSONValue) throws(AgentError) {
    try write(
      .object([
        "jsonrpc": .string("2.0"), "id": id,
        "error": .object(["code": .number(-32601), "message": .string("Method not supported")]),
      ]))
  }

  nonisolated func terminate() { program.terminate() }

  func shutDown(patience: Duration) async {
    program.closeInput()
    let insist = Task { [clock, program] in
      do { try await clock.sleep(for: patience) } catch { return }
      program.terminate()
    }
    if ended == nil { await withCheckedContinuation { whenEnded.append($0) } }
    insist.cancel()
  }

  private func nextID() -> JSONValue {
    sent += 1
    return .string("loci-\(sent)")
  }

  private func write(_ value: JSONValue) throws(AgentError) {
    if let ended { throw ended }
    do { try program.write(OpenCodeRecord.line(value)) } catch { throw .rejected(error.localizedDescription) }
  }

  private func read() async {
    for await chunk in program.output {
      for line in framer.receive(chunk) {
        guard let record = OpenCodeRecord(line: line) else { continue }
        if case .response(let id, let outcome) = record {
          if id == promptID {
            promptID = nil
            promptDeadline?.cancel()
            promptDeadline = nil
            incoming.yield(.settled(outcome))
          } else {
            resolve(id, outcome)
          }
        } else if case .update = record, !forwarding {
          continue
        } else {
          incoming.yield(record)
        }
      }
    }
    open.output = false
    finishIfOver()
  }

  private func readDiagnostics() async {
    for await chunk in program.diagnostics { diagnostics = Data((diagnostics + chunk).suffix(2000)) }
    open.diagnostics = false
    finishIfOver()
  }

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
    let error = AgentError.exited(code: status, diagnostics: String(decoding: diagnostics, as: UTF8.self))
    ended = error
    promptDeadline?.cancel()
    promptDeadline = nil
    for id in Array(waiting.keys) { resolve(id, .failure(error)) }
    incoming.finish()
    for continuation in whenEnded { continuation.resume() }
    whenEnded = []
  }

  private func resolve(_ id: JSONValue, _ outcome: Result<JSONValue, AgentError>) {
    waiting.removeValue(forKey: id)?.resume(returning: outcome)
  }
}
