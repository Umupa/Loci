import Foundation

/// Routes Pi responses to pending requests and hands on everything else.
actor PiChannel {
  nonisolated let records: AsyncStream<PiRecord>
  nonisolated let connection: ProgramConnection

  private let incoming: AsyncStream<PiRecord>.Continuation
  private var sent = 0

  init(program: RunningProgram, clock: any Clock<Duration>) {
    connection = ProgramConnection(program: program, clock: clock)
    (records, incoming) = AsyncStream.makeStream(of: PiRecord.self)
    Task {
      _ = await connection.listen { await self.receive($0) }
      incoming.finish()
    }
  }

  func request(_ command: PiCommand, within limit: Duration) async throws(AgentError) -> JSONValue {
    sent += 1
    let id = "loci-\(sent)"
    return try await connection.request(
      id, data: command.record(id: id).line, operation: command.name, within: limit)
  }

  func send(_ command: PiCommand) async throws(AgentError) {
    try await connection.send(command.record(id: "").line)
  }

  private func receive(_ line: Data) async {
    guard let record = PiRecord(line: line) else { return }
    if case .response(let id, _, let outcome) = record {
      if let id { await connection.resolve(id, outcome) }
    } else {
      incoming.yield(record)
    }
  }
}
