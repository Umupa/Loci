import Foundation
import LociModel

/// `settings.json` at the top of the Loci folder: choices that belong to this host, not to one mentor.
public struct HostSettings: Hashable, Sendable {
  /// The agent new mentors run on; `nil` until one is chosen.
  public var agent: Mentor.Provider?
  /// The model new mentors ask each agent for.
  public var models: [Mentor.Provider: String] = [:]
  public var lessonLanguage: LessonLanguage = .learners
  /// The Whisper model recognition uses; `nil` until one is chosen.
  public var speechModel: SpeechModel?
  public var browserLogin: BrowserLogin = .none

  public init() {}
}

extension HostSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case agent, models, lessonLanguage, newMentors, speechModel, browserLogin
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    agent = try container.decodeIfPresent(Mentor.Provider.self, forKey: .agent)
    models = try container.decodeIfPresent([Mentor.Provider: String].self, forKey: .models) ?? [:]
    let language = try container.decodeIfPresent(String.self, forKey: .lessonLanguage)
    lessonLanguage = language.map(LessonLanguage.fixed) ?? .learners
    speechModel = try? container.decodeIfPresent(SpeechModel.self, forKey: .speechModel)
    browserLogin = (try? container.decodeIfPresent(BrowserLogin.self, forKey: .browserLogin)) ?? BrowserLogin.none
    if agent == nil, let earlier = try container.decodeIfPresent(AgentChoice.self, forKey: .newMentors) {
      agent = earlier.provider
      if let model = earlier.model { models[earlier.provider] = model }
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(agent, forKey: .agent)
    if !models.isEmpty { try container.encode(models, forKey: .models) }
    if case .fixed(let tag) = lessonLanguage { try container.encode(tag, forKey: .lessonLanguage) }
    try container.encodeIfPresent(speechModel, forKey: .speechModel)
    if browserLogin != .none { try container.encode(browserLogin, forKey: .browserLogin) }
  }
}

extension Store {
  static let settingsFile = "settings.json"

  private var settingsURL: URL { root.appending(path: Self.settingsFile) }

  public func settings() throws -> HostSettings {
    do {
      return try decodeJSON(HostSettings.self, at: settingsURL)
    } catch StoreError.notFound {
      return HostSettings()
    }
  }

  /// Rewrites `settings.json` with the change. A file that cannot be read is replaced.
  @discardableResult
  public func changeSettings(_ change: (inout HostSettings) -> Void) throws -> HostSettings {
    var settings = (try? self.settings()) ?? HostSettings()
    change(&settings)
    try write(Formats.document(settings), to: settingsURL)
    return settings
  }
}
