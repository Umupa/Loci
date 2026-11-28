public struct TranslationSettings: Hashable, Codable, Sendable {
  public static let defaultTranscriptPrompt =
    "Translate each line of this transcript into the language with BCP 47 tag `{{language}}`. "
    + "Translate the meaning naturally and keep technical terms recognizable."
  public static let defaultArticlePrompt =
    "Translate each passage of this article into the language with BCP 47 tag `{{language}}`. "
    + "Translate the meaning naturally and keep technical terms recognizable. Keep the Markdown as it is: "
    + "heading marks, emphasis, links and their addresses, inline code and formulas stay unchanged around the translated words."

  /// `nil` translates with the tool model.
  public var model: ModelChoice?
  public var language: String?
  public var smart: Bool
  public var transcriptPrompt: String
  public var articlePrompt: String

  public init(
    model: ModelChoice? = nil, language: String? = nil, smart: Bool = false,
    transcriptPrompt: String = Self.defaultTranscriptPrompt, articlePrompt: String = Self.defaultArticlePrompt
  ) {
    self.model = model
    self.language = language
    self.smart = smart
    self.transcriptPrompt = transcriptPrompt
    self.articlePrompt = articlePrompt
  }
}

/// What a model service is asked for: translating, or anything else done in the background without talking.
public enum ModelUse: String, Codable, CaseIterable, Sendable {
  case tool, translation
}

/// The model services: the providers, the tool model, and how translations are asked for and with which model.
public struct ModelSettings: Hashable, Sendable {
  public var providers: [ModelProvider]
  /// What the background does without talking: chapters, key points, tidying, naming speakers, refreshing panels.
  /// `nil` until one is chosen.
  public var toolModel: ModelChoice?
  public var translation: TranslationSettings

  public init(
    providers: [ModelProvider] = [], toolModel: ModelChoice? = nil,
    translation: TranslationSettings = TranslationSettings()
  ) {
    self.providers = providers
    self.toolModel = toolModel
    self.translation = translation
  }

  /// What `use` is done with: translation's own model, else the tool model.
  public func model(for use: ModelUse) -> ModelChoice? {
    switch use {
    case .tool: toolModel
    case .translation: translation.model ?? toolModel
    }
  }

  /// `nil` when the provider is off or gone, or the model is not checked on it: not configured.
  public func service(for choice: ModelChoice?) -> ModelService? {
    guard let choice, let provider = providers.first(where: { $0.id == choice.provider }) else { return nil }
    return ModelService(provider, model: choice.model)
  }

  /// `choice` when it is configured, else what `use` is done with.
  public func service(preferring choice: ModelChoice?, for use: ModelUse) -> ModelService? {
    service(for: choice) ?? service(for: model(for: use))
  }

  /// The checked models on the providers that are on, by provider.
  public var groups: [ModelGroup] {
    providers.compactMap { provider in
      let models = provider.checkedModels
      guard provider.enabled, provider.address != nil, !models.isEmpty else { return nil }
      return ModelGroup(provider: provider.id, preset: provider.preset, name: provider.name, models: models)
    }
  }

  /// Gives the tool model, when not chosen yet, the first model there is.
  public mutating func fillToolModel() {
    guard toolModel == nil, let first = groups.first?.choices().first else { return }
    toolModel = first
  }
}

extension ModelSettings: Codable {
  private enum CodingKeys: String, CodingKey {
    case providers, toolModel, translation, uses
  }

  /// What versions up to 1.8.5 chose for chapters and key points becomes the tool model; their translation
  /// model is kept apart only when it was another.
  private struct OldUses: Decodable {
    let translation: ModelChoice?
    let transcripts: ModelChoice?
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    providers = try container.decode([ModelProvider].self, forKey: .providers)
    translation = try container.decode(TranslationSettings.self, forKey: .translation)
    if container.contains(.toolModel) || !container.contains(.uses) {
      toolModel = try container.decodeIfPresent(ModelChoice.self, forKey: .toolModel)
      return
    }
    let old = try container.decode(OldUses.self, forKey: .uses)
    toolModel = old.transcripts ?? old.translation
    if translation.model == nil, old.translation != toolModel { translation.model = old.translation }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(providers, forKey: .providers)
    try container.encodeIfPresent(toolModel, forKey: .toolModel)
    try container.encode(translation, forKey: .translation)
  }
}

/// The settings with which providers have a key saved, as the settings page shows them.
public struct ModelSettingsState: Sendable {
  public let settings: ModelSettings
  public let keys: Set<ModelProviderID>
  public let cacheBytes: Int64

  public init(settings: ModelSettings, keys: Set<ModelProviderID>, cacheBytes: Int64) {
    self.settings = settings
    self.keys = keys
    self.cacheBytes = cacheBytes
  }
}

/// Settings and credentials on the Mac running the model requests. Every change is saved as it is made.
public protocol ModelSettingsAccess: Sendable {
  func readModelSettings() async throws(HostError) -> ModelSettingsState
  func saveModelSettings(_ settings: ModelSettings) async throws(HostError) -> ModelSettingsState
  /// Saves `key` for the provider, or removes it when `nil`.
  func setModelKey(_ key: String?, for provider: ModelProviderID) async throws(HostError) -> ModelSettingsState
  /// The key saved for the provider.
  func modelKey(for provider: ModelProviderID) async throws(HostError) -> String?
  /// Asks the provider for its models and adds the new ones, unchecked.
  func fetchModels(for provider: ModelProviderID) async throws(HostError) -> ModelSettingsState
  /// Asks `model`, or the provider's first, for a short answer and says how long it took.
  func testModel(_ model: String?, on provider: ModelProviderID) async throws(HostError) -> Duration
  func clearTranslationCache() async throws(HostError)
  func needsModelSetup() async -> Bool
}

extension ModelSettingsAccess {
  public func needsModelSetup() async -> Bool { false }
}

extension Host {
  public func modelSettingsAccess() async -> (any ModelSettingsAccess)? { nil }
}

/// What the menus offer: the checked models on the providers that are on, the tool model, and what translation
/// is done with.
public struct ModelOptions: Hashable, Sendable {
  public let groups: [ModelGroup]
  public let toolModel: ModelChoice?
  /// Translation's own model, else the tool model.
  public let translationModel: ModelChoice?

  public init(groups: [ModelGroup], toolModel: ModelChoice?, translationModel: ModelChoice?) {
    self.groups = groups
    self.toolModel = toolModel
    self.translationModel = translationModel
  }

  public static let none = ModelOptions(groups: [], toolModel: nil, translationModel: nil)

  public func offers(_ choice: ModelChoice?) -> Bool {
    guard let choice else { return false }
    return groups.contains { $0.provider == choice.provider && $0.models.contains(choice.model) }
  }

  /// `choice` when it is offered, else what `use` is done with when that is; `nil` when neither is.
  public func model(preferring choice: ModelChoice?, for use: ModelUse) -> ModelChoice? {
    if offers(choice) { return choice }
    let fallback =
      switch use {
      case .tool: toolModel
      case .translation: translationModel
      }
    return offers(fallback) ? fallback : nil
  }
}

extension ModelOptions: Codable {
  private enum CodingKeys: String, CodingKey {
    case groups, toolModel, translationModel, uses
  }

  /// A Mac on 1.8.5 or before says what each use is done with instead.
  private struct OldUses: Decodable {
    let translation: ModelChoice?
    let transcripts: ModelChoice?
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    groups = try container.decode([ModelGroup].self, forKey: .groups)
    if let old = try container.decodeIfPresent(OldUses.self, forKey: .uses) {
      toolModel = old.transcripts
      translationModel = old.translation
    } else {
      toolModel = try container.decodeIfPresent(ModelChoice.self, forKey: .toolModel)
      translationModel = try container.decodeIfPresent(ModelChoice.self, forKey: .translationModel)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(groups, forKey: .groups)
    try container.encodeIfPresent(toolModel, forKey: .toolModel)
    try container.encodeIfPresent(translationModel, forKey: .translationModel)
  }
}

/// The models the menus offer, kept current.
public struct AvailableModels: Subscription {
  public static let name = "models"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> ModelOptions {
    try await handler.modelOptions()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains(.everything)
  }
}
