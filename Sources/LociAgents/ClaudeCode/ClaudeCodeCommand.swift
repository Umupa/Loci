import Foundation

enum ClaudeCodeCommand: Hashable, Sendable {
  case control(String)
  case prompt(String)
  case reply(ClaudeCodeDialog, allow: Bool)

  var name: String {
    switch self {
    case .control(let subtype): subtype
    case .prompt: "user"
    case .reply: "control_response"
    }
  }

  func record(id: String) -> JSONValue {
    switch self {
    case .control(let subtype):
      return .object([
        "type": .string("control_request"), "request_id": .string(id),
        "request": .object(["subtype": .string(subtype)]),
      ])
    case .prompt(let text):
      return .object([
        "type": .string("user"), "session_id": .string(""), "parent_tool_use_id": .null,
        "message": .object([
          "role": .string("user"), "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
        ]),
      ])
    case .reply(let dialog, let allow):
      let response: JSONValue =
        allow
        ? .object(["behavior": .string("allow"), "updatedInput": dialog.input])
        : .object(["behavior": .string("deny"), "message": .string("User declined tool execution.")])
      return .object([
        "type": .string("control_response"),
        "response": .object([
          "subtype": .string("success"), "request_id": .string(dialog.id), "response": response,
        ]),
      ])
    }
  }

  func line(id: String) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = (try? encoder.encode(record(id: id))) ?? Data()
    data.append(0x0A)
    return data
  }
}
