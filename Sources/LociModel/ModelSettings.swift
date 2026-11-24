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

/// What translation, and chapters and key points, are done with.
public enum ModelUse: String, Codable, CaseIterable, Sendable {
  case translation, transcripts
}

/// The model each use is done with; `nil` until one is chosen.
public struct ModelUses: Hashable, Codable, Sendable {
  public var translation: ModelChoice?
  public var transcripts: ModelChoice?

  public init(translation: ModelChoice? = nil, transcripts: ModelChoice? = nil) {
    self.translation = translation
    self.transcripts = transcripts
  }

  public subscript(use: ModelUse) -> ModelChoice? {
    get {
      switch use {
      case .translation: translation
      case .transcripts: transcripts
      }
    }
    set {
      switch use {
      case .translation: translation = newValue
      case .transcripts: transcripts = newValue
      }
    }
  }
}

/// The model services: the providers, what each use is done with, and how translations are asked for.
public struct ModelSettings: Hashable, Codable, Sendable {
  public var providers: [ModelProvider]
  public var uses: ModelUses
  public var translation: TranslationSettings

  public init(
    providers: [ModelProvider] = [], uses: ModelUses = ModelUses(),
    translation: TranslationSettings = TranslationSettings()
  ) {
    self.providers = providers
    self.uses = uses
    self.translation = translation
  }

  /// `nil` when the provider is off or gone, or the model is not checked on it: not configured.
  public func service(for choice: ModelChoice?) -> ModelService? {
    guard let choice, let provider = providers.first(where: { $0.id == choice.provider }) else { return nil }
    return ModelService(provider, model: choice.model)
  }

  /// `choice` when it is configured, else what `use` is done with.
  public func service(preferring choice: ModelChoice?, for use: ModelUse) -> ModelService? {
    service(for: choice) ?? service(for: uses[use])
  }

  /// The checked models on the providers that are on, by provider.
  public var groups: [ModelGroup] {
    providers.compactMap { provider in
      let models = provider.checkedModels
      guard provider.enabled, provider.address != nil, !models.isEmpty else { return nil }
      return ModelGroup(provider: provider.id, preset: provider.preset, name: provider.name, models: models)
    }
  }

  /// Gives each use not chosen yet the first model there is.
  public mutating func fillUses() {
    guard let first = groups.first?.choices().first else { return }
    for use in ModelUse.allCases where uses[use] == nil { uses[use] = first }
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
  /// The key saved for the provider; reading it may ask the person to allow Loci into the keychain.
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

/// What the menus offer: the checked models on the providers that are on, and what each use is done with.
public struct ModelOptions: Hashable, Codable, Sendable {
  public let groups: [ModelGroup]
  public let uses: ModelUses

  public init(groups: [ModelGroup], uses: ModelUses) {
    self.groups = groups
    self.uses = uses
  }

  public static let none = ModelOptions(groups: [], uses: ModelUses())

  public func offers(_ choice: ModelChoice?) -> Bool {
    guard let choice else { return false }
    return groups.contains { $0.provider == choice.provider && $0.models.contains(choice.model) }
  }

  /// `choice` when it is offered, else what `use` is done with when that is; `nil` when neither is.
  public func model(preferring choice: ModelChoice?, for use: ModelUse) -> ModelChoice? {
    if offers(choice) { return choice }
    return offers(uses[use]) ? uses[use] : nil
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
