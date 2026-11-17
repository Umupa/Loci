import Foundation

/// A long-lived agent responsible for one subject; the contents of `mentor.json`.
public struct Mentor: Hashable, Sendable {
  public let id: EntityID
  public let name: String
  /// The name of one of the built-in ink portraits.
  public let avatar: String
  public let color: MentorColor
  public let provider: Provider
  /// The model to ask the provider for; `nil` leaves the choice to the provider.
  public let model: String?
  public let permission: Permission
  /// The sentence the mentor was created from: what the person wants to learn.
  public let request: String?

  public init(
    id: EntityID, name: String, avatar: String, color: MentorColor, provider: Provider, model: String? = nil,
    permission: Permission, request: String? = nil
  ) throws {
    self.id = id
    self.name = try name.requiringText("name")
    self.avatar = try avatar.requiringText("avatar")
    self.color = color
    self.provider = provider
    self.model = try model.requiringText("model")
    self.permission = permission
    self.request = try request.requiringText("request")
  }

  /// The names of the built-in portraits, in the order new mentors are given them.
  ///
  /// Carried over from the previous version; the set is redrawn with the visual design.
  public static let portraits = [
    "ember", "wisp", "dew", "moss", "nimbus", "pebble", "luna", "nova", "flint", "tide", "juniper", "wren", "ash",
    "quill",
  ]

  /// The agent command-line program that runs the mentor.
  public enum Provider: String, CaseIterable, Codable, Hashable, Sendable {
    case pi
    case omp
    case grok
    case antigravity
    case cursor
    case fx
    case hermes
    case claudeCode = "claude-code"
    case codex
    case opencode
  }

  /// How much the mentor may do without asking.
  public enum Permission: String, CaseIterable, Codable, Hashable, Sendable {
    case ask
    case full
  }
}

extension Mentor: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, avatar, color, provider, model, permission, request
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(EntityID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let avatar = try container.decode(String.self, forKey: .avatar)
    let color = try container.decode(MentorColor.self, forKey: .color)
    let provider = try container.decode(Provider.self, forKey: .provider)
    let model = try container.decodeIfPresent(String.self, forKey: .model)
    let permission = try container.decode(Permission.self, forKey: .permission)
    let request = try container.decodeIfPresent(String.self, forKey: .request)
    self = try decoder.validated {
      try Mentor(
        id: id, name: name, avatar: avatar, color: color, provider: provider, model: model, permission: permission,
        request: request)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(avatar, forKey: .avatar)
    try container.encode(color, forKey: .color)
    try container.encode(provider, forKey: .provider)
    try container.encodeIfPresent(model, forKey: .model)
    try container.encode(permission, forKey: .permission)
    try container.encodeIfPresent(request, forKey: .request)
  }
}
