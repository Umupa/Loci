struct CodexDialog: Sendable {
  let id: JSONValue
  let method: String
  let params: JSONValue

  init?(id: JSONValue, method: String, params: JSONValue) {
    guard
      [
        "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
        "item/permissions/requestApproval",
      ].contains(method)
    else { return nil }
    self.id = id
    self.method = method
    self.params = params
  }

  var key: String { Self.key(for: id) }

  /// How a request is known to the caller, from its JSON-RPC id.
  static func key(for id: JSONValue) -> String {
    switch id {
    case .string(let value): "string:\(value)"
    case .number(let value): "number:\(value)"
    default: "invalid"
    }
  }

  var request: PermissionRequest {
    PermissionRequest(
      id: .init(key), title: params["command"]?.string ?? params["reason"]?.string ?? method,
      toolCall: params["itemId"]?.string.map(ToolCall.ID.init),
      options: [.init(id: "accept", role: .allow), .init(id: "decline", role: .deny)])
  }

  func reply(to answer: PermissionAnswer) -> JSONValue {
    let decision: String
    switch answer {
    case .chosen("accept"): decision = "accept"
    case .chosen("decline"): decision = "decline"
    default: decision = "cancel"
    }
    let result: JSONValue
    if method == "item/permissions/requestApproval" {
      let permissions: JSONValue
      if decision == "accept", case .object(let requested) = params["permissions"] {
        permissions = .object(requested.filter { $0.value != .null })
      } else {
        permissions = .object([:])
      }
      result = .object([
        "permissions": permissions,
        "scope": .string("turn"),
      ])
    } else {
      result = .object(["decision": .string(decision)])
    }
    return CodexCommand.reply(id, result: result)
  }
}
