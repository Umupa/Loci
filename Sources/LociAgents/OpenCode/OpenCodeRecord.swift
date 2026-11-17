import Foundation

enum OpenCodeRecord: Sendable {
  case response(JSONValue, Result<JSONValue, AgentError>)
  case update(session: String, JSONValue)
  case request(id: JSONValue, method: String, params: JSONValue)
  case settled(Result<JSONValue, AgentError>)

  init?(line: Data) {
    guard let record = try? JSONDecoder().decode(JSONValue.self, from: line), record["jsonrpc"]?.string == "2.0"
    else { return nil }
    if let method = record["method"]?.string {
      let params = record["params"] ?? .object([:])
      if let id = record["id"] {
        self = .request(id: id, method: method, params: params)
      } else if method == "session/update", let session = params["sessionId"]?.string, let update = params["update"] {
        self = .update(session: session, update)
      } else {
        return nil
      }
    } else if let id = record["id"] {
      if let error = record["error"] {
        let message = error["message"]?.string ?? "OpenCode request failed"
        let detail = error["data"]?["details"]?.string ?? error["data"]?["message"]?.string
        let words = detail.map { "\(message): \($0)" } ?? message
        self = .response(id, .failure(.rejected(words)))
      } else if let result = record["result"] {
        self = .response(id, .success(result))
      } else {
        return nil
      }
    } else {
      return nil
    }
  }

  static func line(_ value: JSONValue) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)
    return data
  }
}
