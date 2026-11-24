import Foundation
import LociModel

enum CodexRecord: Sendable {
  case response(String, Result<JSONValue, AgentError>)
  case request(id: JSONValue, method: String, params: JSONValue)
  case notification(method: String, params: JSONValue)

  init?(line: Data) {
    guard let record = try? JSONDecoder().decode(JSONValue.self, from: line) else { return nil }
    if let method = record["method"]?.string {
      let params = record["params"] ?? .null
      if let id = record["id"] {
        self = .request(id: id, method: method, params: params)
      } else {
        self = .notification(method: method, params: params)
      }
    } else if let id = record["id"]?.string {
      if let error = record["error"] {
        self = .response(id, .failure(.rejected(error["message"]?.string ?? "Codex request failed")))
      } else if let result = record["result"] {
        self = .response(id, .success(result))
      } else {
        return nil
      }
    } else {
      return nil
    }
  }
}
