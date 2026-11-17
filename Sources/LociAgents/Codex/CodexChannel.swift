import Foundation

actor CodexChannel {
  nonisolated let records: AsyncStream<CodexRecord>

  private let program: RunningProgram
  private let clock: any Clock<Duration>
  private let incoming: AsyncStream<CodexRecord>.Continuation
  private var framer = LineFramer()
  private var sent = 0
  private var waiting: [String: CheckedContinuation<Result<JSONValue, AgentError>, Never>] = [:]
  private var diagnostics = Data()
  private var open = (output: true, diagnostics: true)
  private var status: Int32?
  private var whenEnded: [CheckedContinuation<Void, Never>] = []
  private(set) var ended: AgentError?

  init(program: RunningProgram, clock: any Clock<Duration>) {
    self.program = program
    self.clock = clock
    (records, incoming) = AsyncStream.makeStream(of: CodexRecord.self)
    Task { await self.read() }
    Task { await self.readDiagnostics() }
    Task { await self.watchExit() }
  }

  func request(_ method: String, params: JSONValue, within limit: Duration) async throws(AgentError) -> JSONValue {
    if let ended { throw ended }
    sent += 1
    let id = "loci-\(sent)"
    let deadline = Task { [clock] in
      do { try await clock.sleep(for: limit) } catch { return }
      self.resolve(id, .failure(.unresponsive(method)))
    }
    let outcome = await withCheckedContinuation { continuation in
      waiting[id] = continuation
      do {
        try program.write(CodexCommand.line(CodexCommand.request(method, params: params, id: id)))
      } catch {
        resolve(id, .failure(.rejected(error.localizedDescription)))
      }
    }
    deadline.cancel()
    return try outcome.get()
  }

  func send(_ record: JSONValue) throws(AgentError) {
    if let ended { throw ended }
    do { try program.write(CodexCommand.line(record)) } catch { throw .rejected(error.localizedDescription) }
  }

  nonisolated func terminate() {
    program.terminate()
  }

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
        guard let record = CodexRecord(line: line) else { continue }
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
