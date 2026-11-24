import Foundation
import LociModel

enum ClaudeCodeCommand: Hashable, Sendable {
  case control(String)
  case prompt(String)
  case refuse(String)
  case reply(ClaudeCodeDialog, allow: Bool)

  var name: String {
    switch self {
    case .control(let subtype): subtype
    case .prompt: "user"
    case .reply, .refuse: "control_response"
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
    case .refuse(let request):
      return .object([
        "type": .string("control_response"),
        "response": .object([
          "subtype": .string("error"), "request_id": .string(request),
          "error": .string("Unsupported Claude Code control request"),
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
}
