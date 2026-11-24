import Foundation
import LociModel

/// A JSON-RPC message read from an ACP agent's standard output.
enum AcpRecord: Hashable, Sendable {
  /// The answer to one of the client's requests.
  case response(id: Int, outcome: Result<JSONValue, AgentError>)
  /// The agent asks the client something and waits for the answer.
  case request(id: JSONValue, method: String, params: JSONValue)
  case notification(method: String, params: JSONValue)
  case promptFinished(Result<JSONValue, AgentError>)

  init?(line: Data) {
    guard let record = try? JSONDecoder().decode(JSONValue.self, from: line) else { return nil }
    if let method = record["method"]?.string {
      let params = record["params"] ?? .null
      if let id = record["id"], id != .null {
        self = .request(id: id, method: method, params: params)
      } else {
        self = .notification(method: method, params: params)
      }
    } else if let id = record["id"]?.int {
      if let error = record["error"] {
        self = .response(id: id, outcome: .failure(Self.failure(error)))
      } else {
        self = .response(id: id, outcome: .success(record["result"] ?? .null))
      }
    } else {
      return nil
    }
  }

  /// The agent's own explanation, preferring the detail in `data` over the bare message.
  private static func failure(_ error: JSONValue) -> AgentError {
    if error["data"]?["code"]?.string == "FS_NOT_FOUND" { return .sessionNotFound }
    if error["code"]?.int == -32002, error["data"]?["sessionId"]?.string != nil { return .sessionNotFound }
    let detail =
      error["data"]?["details"]?.string ?? error["data"]?["message"]?.string
      ?? error["data"]?.string ?? error["data"]?["detail"]?.string
    let message = error["message"]?.string ?? ""
    let words = [message, detail ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
    return .rejected(words.isEmpty ? "the agent refused the request" : words)
  }
}

/// A record written to an ACP agent's standard input.
enum AcpOutgoing {
  static func request(id: Int, method: String, params: JSONValue) -> Data {
    line(["jsonrpc": .string("2.0"), "id": .integer(Int64(id)), "method": .string(method), "params": params])
  }

  static func notification(method: String, params: JSONValue) -> Data {
    line(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
  }

  static func result(id: JSONValue, _ result: JSONValue) -> Data {
    line(["jsonrpc": .string("2.0"), "id": id, "result": result])
  }

  static func methodNotFound(id: JSONValue, _ method: String) -> Data {
    line([
      "jsonrpc": .string("2.0"), "id": id,
      "error": .object(["code": .integer(-32601), "message": .string("Method not found: \(method)")]),
    ])
  }

  private static func line(_ members: [String: JSONValue]) -> Data {
    JSONValue.object(members).line
  }
}
