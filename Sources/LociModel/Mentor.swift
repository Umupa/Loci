import Foundation

/// A long-lived agent responsible for one subject; the contents of `mentor.json`.
public struct Mentor: Hashable, Sendable {
  public let id: EntityID
  public let name: String
  /// The name of the mentor's sign, one of `Mark`; a name from an earlier version is still kept.
  public let avatar: String
  public let color: MentorColor
  public let provider: Provider
  /// The model to ask the provider for; `nil` leaves the choice to the provider.
  public let model: String?
  /// How hard the agent thinks; `nil` leaves it to the provider. Always one of `provider.efforts`: an effort the
  /// provider does not offer is dropped when the mentor is made.
  public let effort: ThinkingEffort?
  /// The sentence the mentor was created from: what the person wants to learn.
  public let request: String?

  public init(
    id: EntityID, name: String, avatar: String, color: MentorColor, provider: Provider, model: String? = nil,
    effort: ThinkingEffort? = nil, request: String? = nil
  ) throws {
    self.id = id
    self.name = try name.requiringText("name")
    self.avatar = try avatar.requiringText("avatar")
    self.color = color
    self.provider = provider
    self.model = try model.requiringText("model")
    self.effort = effort.flatMap { provider.efforts.contains($0) ? $0 : nil }
    self.request = try request.requiringText("request")
  }

  /// The agent command-line program that runs the mentor.
  public enum Provider: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable {
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
}

extension Mentor: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, name, avatar, color, provider, model, effort, request
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(EntityID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let avatar = try container.decode(String.self, forKey: .avatar)
    let color = try container.decode(MentorColor.self, forKey: .color)
    let provider = try container.decode(Provider.self, forKey: .provider)
    let model = try container.decodeIfPresent(String.self, forKey: .model)
    let effort = try container.decodeIfPresent(ThinkingEffort.self, forKey: .effort)
    let request = try container.decodeIfPresent(String.self, forKey: .request)
    self = try decoder.validated {
      try Mentor(
        id: id, name: name, avatar: avatar, color: color, provider: provider, model: model, effort: effort,
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
    try container.encodeIfPresent(effort, forKey: .effort)
    try container.encodeIfPresent(request, forKey: .request)
  }
}
