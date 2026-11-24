import Foundation
import LociModel

/// Routes ACP responses, prompt completion, and live session messages.
actor AcpChannel {
  nonisolated let records: AsyncStream<AcpRecord>
  nonisolated let connection: ProgramConnection

  private let incoming: AsyncStream<AcpRecord>.Continuation
  private var sent = 0
  private var promptID: Int?
  private var forwarding = false

  init(program: RunningProgram, clock: any Clock<Duration>) {
    connection = ProgramConnection(program: program, clock: clock)
    (records, incoming) = AsyncStream.makeStream(of: AcpRecord.self)
    Task {
      _ = await connection.listen { await self.receive($0) }
      incoming.finish()
    }
  }

  /// Delivers live updates after setup, leaving history replayed during session loading behind.
  func beginSession() {
    forwarding = true
  }

  func request(_ method: String, _ params: JSONValue, within limit: Duration) async throws(AgentError) -> JSONValue {
    sent += 1
    let id = sent
    return try await connection.request(
      String(id), data: AcpOutgoing.request(id: id, method: method, params: params), operation: method, within: limit)
  }

  func notify(_ method: String, _ params: JSONValue) async throws(AgentError) {
    try await connection.send(AcpOutgoing.notification(method: method, params: params))
  }

  func prompt(_ params: JSONValue) async throws(AgentError) {
    sent += 1
    promptID = sent
    do {
      try await connection.send(AcpOutgoing.request(id: sent, method: "session/prompt", params: params))
    } catch {
      promptID = nil
      throw error
    }
  }

  func respond(to id: JSONValue, with result: JSONValue) async throws(AgentError) {
    try await connection.send(AcpOutgoing.result(id: id, result))
  }

  func refuse(_ id: JSONValue, method: String) async throws(AgentError) {
    try await connection.send(AcpOutgoing.methodNotFound(id: id, method))
  }

  private func receive(_ line: Data) async {
    guard let record = AcpRecord(line: line) else { return }
    if case .response(let id, let outcome) = record {
      if id == promptID {
        promptID = nil
        incoming.yield(.promptFinished(outcome))
      } else {
        await connection.resolve(String(id), outcome)
      }
    } else if forwarding {
      incoming.yield(record)
    } else if case .request(let id, let method, _) = record {
      if method == "session/request_permission" {
        try? await respond(to: id, with: AcpTurnState.cancelled)
      } else {
        try? await refuse(id, method: method)
      }
    }
  }
}
