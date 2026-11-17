import Foundation

/// Routes ClaudeCode responses to pending requests and hands on everything else.
actor ClaudeCodeChannel {
  nonisolated let records: AsyncStream<ClaudeCodeRecord>
  nonisolated let connection: ProgramConnection

  private let incoming: AsyncStream<ClaudeCodeRecord>.Continuation
  private var sent = 0

  init(program: RunningProgram, clock: any Clock<Duration>) {
    connection = ProgramConnection(program: program, clock: clock)
    (records, incoming) = AsyncStream.makeStream(of: ClaudeCodeRecord.self)
    Task {
      _ = await connection.listen { await self.receive($0) }
      incoming.finish()
    }
  }

  func request(_ command: ClaudeCodeCommand, within limit: Duration) async throws(AgentError) -> JSONValue {
    sent += 1
    let id = "loci-\(sent)"
    return try await connection.request(
      id, data: command.record(id: id).line, operation: command.name, within: limit)
  }

  func send(_ command: ClaudeCodeCommand) async throws(AgentError) {
    try await connection.send(command.record(id: "").line)
  }

  private func receive(_ line: Data) async {
    guard let record = ClaudeCodeRecord(line: line) else { return }
    if case .response(let id, let outcome) = record {
      await connection.resolve(id, outcome)
    } else {
      incoming.yield(record)
    }
  }
}
