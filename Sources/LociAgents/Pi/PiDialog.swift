import Foundation

/// A question from a Pi extension that waits for an answer.
struct PiDialog: Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    case confirm
    case select([String])
  }

  enum Reply: Hashable, Sendable {
    case confirmed(Bool)
    case value(String)
    case cancelled
  }

  /// The title Loci's own extension gives its dialogs; their message is JSON naming the tool call.
  static let ownTitle = "loci:permission"
  private static let allow = "allow"
  private static let deny = "deny"

  let id: String
  let kind: Kind
  let title: String
  let message: String

  var request: PermissionRequest {
    let options: [PermissionRequest.Option]
    switch kind {
    case .confirm:
      options = [.init(id: Self.allow, role: .allow), .init(id: Self.deny, role: .deny)]
    case .select(let labels):
      options = labels.enumerated().map { .init(id: String($0.offset), role: .choice, label: $0.element.plain) }
    }
    if title == Self.ownTitle, let own = try? JSONDecoder().decode(JSONValue.self, from: Data(message.utf8)),
      let tool = own["toolName"]?.string, let call = own["toolCallId"]?.string
    {
      return PermissionRequest(id: .init(id), title: tool, toolCall: .init(call), options: options)
    }
    let text = [title, message].filter { !$0.isEmpty }.joined(separator: " — ")
    return PermissionRequest(id: .init(id), title: text.plain, options: options)
  }

  func reply(to answer: PermissionAnswer) -> PiCommand {
    .reply(dialog: id, reply(for: answer))
  }

  private func reply(for answer: PermissionAnswer) -> Reply {
    guard case .chosen(let option) = answer else { return .cancelled }
    switch kind {
    case .confirm:
      if option == Self.allow { return .confirmed(true) }
      return option == Self.deny ? .confirmed(false) : .cancelled
    case .select(let labels):
      guard let index = Int(option), labels.indices.contains(index) else { return .cancelled }
      return .value(labels[index])
    }
  }
}

extension String {
  /// The text without terminal escape sequences, which Pi's extensions emit even when no terminal is attached.
  var plain: String {
    self.replacing(#/\x{1B}\][^\x{07}\x{1B}]*(?:\x{07}|\x{1B}\\)/#, with: "")
      .replacing(#/\x{1B}\[[0-?]*[ -\/]*[@-~]/#, with: "")
  }
}
