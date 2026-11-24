import Foundation
import LociModel

/// Routes Codex responses to pending requests and hands on everything else.
actor CodexChannel {
  nonisolated let records: AsyncStream<CodexRecord>
  nonisolated let connection: ProgramConnection

  private let incoming: AsyncStream<CodexRecord>.Continuation
  private var sent = 0

  init(program: RunningProgram, clock: any Clock<Duration>) {
    connection = ProgramConnection(program: program, clock: clock)
    (records, incoming) = AsyncStream.makeStream(of: CodexRecord.self)
    Task {
      _ = await connection.listen { await self.receive($0) }
      incoming.finish()
    }
  }

  func request(_ method: String, params: JSONValue, within limit: Duration) async throws(AgentError) -> JSONValue {
    sent += 1
    let id = "loci-\(sent)"
    return try await connection.request(
      id, data: CodexCommand.request(method, params: params, id: id).line, operation: method, within: limit)
  }

  func send(_ record: JSONValue) async throws(AgentError) {
    try await connection.send(record.line)
  }

  private func receive(_ line: Data) async {
    guard let record = CodexRecord(line: line) else { return }
    if case .response(let id, let outcome) = record {
      await connection.resolve(id, outcome)
    } else {
      incoming.yield(record)
    }
  }
}
