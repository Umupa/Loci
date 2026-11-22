public struct TranslationSettings: Hashable, Codable, Sendable {
  public static let defaultTranscriptPrompt =
    "Translate each line of this transcript into the language with BCP 47 tag `{{language}}`. "
    + "Translate the meaning naturally and keep technical terms recognizable."
  public static let defaultArticlePrompt =
    "Translate each passage of this article into the language with BCP 47 tag `{{language}}`. "
    + "Translate the meaning naturally and keep technical terms recognizable. Keep the Markdown as it is: "
    + "heading marks, emphasis, links and their addresses, inline code and formulas stay unchanged around the translated words."

  public var language: String?
  public var smart: Bool
  public var transcriptPrompt: String
  public var articlePrompt: String

  public init(
    language: String? = nil, smart: Bool = false, transcriptPrompt: String = Self.defaultTranscriptPrompt,
    articlePrompt: String = Self.defaultArticlePrompt
  ) {
    self.language = language
    self.smart = smart
    self.transcriptPrompt = transcriptPrompt
    self.articlePrompt = articlePrompt
  }
}

public struct ModelSettings: Hashable, Codable, Sendable {
  public var service: ModelService?
  public var translation: TranslationSettings

  public init(service: ModelService? = nil, translation: TranslationSettings = TranslationSettings()) {
    self.service = service
    self.translation = translation
  }
}

public struct ModelSettingsState: Sendable {
  public let settings: ModelSettings
  public let hasKey: Bool
  public let cacheBytes: Int64

  public init(settings: ModelSettings, hasKey: Bool, cacheBytes: Int64) {
    self.settings = settings
    self.hasKey = hasKey
    self.cacheBytes = cacheBytes
  }
}

public enum ModelKeyChange: Sendable {
  case keep
  case replace(String)
  case remove
}

/// Settings and credentials on the Mac running the model requests.
public protocol ModelSettingsAccess: Sendable {
  func readModelSettings() async throws(HostError) -> ModelSettingsState
  func saveModelSettings(_ settings: ModelSettings, key: ModelKeyChange) async throws(HostError) -> ModelSettingsState
  func testModelService(_ service: ModelService, key: String?) async throws(HostError)
  func clearTranslationCache() async throws(HostError)
  func needsModelSetup() async -> Bool
}

extension ModelSettingsAccess {
  public func needsModelSetup() async -> Bool { false }
}

extension Host {
  public func modelSettingsAccess() async -> (any ModelSettingsAccess)? { nil }
}
