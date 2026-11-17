import Foundation

enum ClaudeCodeRecord: Hashable, Sendable {
  case response(id: String, outcome: Result<JSONValue, AgentError>)
  case message(JSONValue)

  init?(line: Data) {
    guard let record = try? JSONDecoder().decode(JSONValue.self, from: line), record["type"]?.string != nil
    else { return nil }
    if record["type"]?.string == "control_response", let response = record["response"],
      let id = response["request_id"]?.string
    {
      let outcome: Result<JSONValue, AgentError> =
        response["subtype"]?.string == "error"
        ? .failure(.rejected(response["error"]?.string ?? "control_response"))
        : .success(response["response"] ?? .null)
      self = .response(id: id, outcome: outcome)
    } else {
      self = .message(record)
    }
  }
}
