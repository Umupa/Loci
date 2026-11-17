import Foundation

struct OpenCodeDialog: Sendable {
  let id: JSONValue
  let request: PermissionRequest

  init?(id: JSONValue, params: JSONValue) {
    let identifier: String
    switch id {
    case .string(let value): identifier = value
    case .number(let value): identifier = String(format: "%.0f", value)
    default: return nil
    }
    self.id = id
    let call = params["toolCall"]
    let options = (params["options"]?.array ?? []).compactMap { option -> PermissionRequest.Option? in
      guard let id = option["optionId"]?.string else { return nil }
      let role: PermissionRequest.Option.Role
      switch option["kind"]?.string {
      case "allow_once": role = .allow
      case "allow_always": role = .allowAlways
      case "reject_once": role = .deny
      case "reject_always": role = .denyAlways
      default: role = .choice
      }
      return .init(id: id, role: role, label: option["name"]?.string)
    }
    request = PermissionRequest(
      id: .init(identifier), title: call?["title"]?.string ?? "OpenCode",
      toolCall: call?["toolCallId"]?.string.map(ToolCall.ID.init), options: options)
  }

  func reply(to answer: PermissionAnswer) -> JSONValue {
    if case .chosen(let option) = answer, request.options.contains(where: { $0.id == option }) {
      return .object(["outcome": .object(["outcome": .string("selected"), "optionId": .string(option)])])
    }
    return .object(["outcome": .object(["outcome": .string("cancelled")])])
  }
}
