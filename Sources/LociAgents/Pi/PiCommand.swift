import Foundation

/// A record written to Pi's standard input.
enum PiCommand: Hashable, Sendable {
  case getState
  case getSessionStats
  case prompt(String)
  case abort
  case reply(dialog: String, PiDialog.Reply)

  var name: String {
    switch self {
    case .getState: "get_state"
    case .getSessionStats: "get_session_stats"
    case .prompt: "prompt"
    case .abort: "abort"
    case .reply: "extension_ui_response"
    }
  }

  /// The record as JSON. `id` is how Pi's response finds its way back; dialog replies carry the dialog's own.
  func record(id: String) -> JSONValue {
    var members: [String: JSONValue] = ["type": .string(name), "id": .string(id)]
    switch self {
    case .getState, .getSessionStats, .abort:
      break
    case .prompt(let message):
      members["message"] = .string(message)
    case .reply(let dialog, let reply):
      members["id"] = .string(dialog)
      switch reply {
      case .confirmed(let yes): members["confirmed"] = .bool(yes)
      case .value(let value): members["value"] = .string(value)
      case .cancelled: members["cancelled"] = .bool(true)
      }
    }
    return .object(members)
  }
}
