import Foundation
import LociMedia
import LociModel
import LociStore

actor ModelServices {
  let gate: Gate
  let parallelism: Int
  let cache: TranslationCache
  private let store: Store
  private let keys: (any ModelKeyStore)?
  private let client: ModelClient
  private var piCredentialRevision = 0

  init(store: Store, environment: HostEnvironment) {
    self.store = store
    keys = environment.modelKeys
    client = environment.modelClient
    parallelism = environment.modelParallelism
    gate = Gate(limit: parallelism)
    cache = TranslationCache(store: store)
  }

  func configuration() throws(HostError) -> ModelSettings {
    try attempt { try store.modelSettings() }
  }

  func read() async throws(HostError) -> ModelSettingsState {
    let bytes = await cache.bytes()
    let settings = try configuration()
    return try state(for: settings, bytes: bytes)
  }

  func save(_ settings: ModelSettings, key: ModelKeyChange) async throws(HostError) -> ModelSettingsState {
    let bytes = await cache.bytes()
    let before = try configuration()
    let changed: (ModelService, String?)?
    switch key {
    case .keep: changed = nil
    case .replace(let value):
      guard let service = settings.service, let value = Self.cleaned(value), keys != nil else {
        throw .invalidRequest("Choose a model service and enter an API key.")
      }
      changed = (service, value)
    case .remove:
      changed = (settings.service ?? before.service).map { ($0, nil) }
    }
    try attempt { try store.saveModelSettings(settings) }
    if let (service, value) = changed {
      do {
        try keys?.setKey(value, for: service)
        piCredentialRevision += 1
      } catch {
        try attempt { try store.saveModelSettings(before) }
        throw .storage("Keychain (\(error.status))")
      }
    }
    return try state(for: settings, bytes: bytes)
  }

  private func state(for settings: ModelSettings, bytes: Int64) throws(HostError) -> ModelSettingsState {
    let key = if let service = settings.service { try storedKey(for: service) } else { nil as String? }
    return ModelSettingsState(settings: settings, hasKey: key != nil, cacheBytes: bytes)
  }

  func test(_ service: ModelService, key: String?) async throws(HostError) {
    let credential = if let supplied = Self.cleaned(key) { supplied } else { try storedKey(for: service) }
    guard let key = credential else {
      throw .invalidRequest("Enter an API key.")
    }
    let client = client
    try await gate.through { () async throws(HostError) in
      guard !Task.isCancelled else { throw .invalidRequest("The request was cancelled.") }
      do throws(FetchError) {
        try await client.test(service, key: key)
      } catch {
        throw .invalidRequest(error.reason)
      }
    }
  }

  struct PiCredential: Sendable {
    let service: ModelService
    let key: String?
    let revision: Int
  }

  func piCredential() throws(HostError) -> PiCredential? {
    guard let service = try configuration().service else { return nil }
    return PiCredential(service: service, key: try storedKey(for: service), revision: piCredentialRevision)
  }

  func selection() throws(HostError) -> (TranslationSettings, ModelTranscriptAgent?) {
    let settings = try configuration()
    guard let service = settings.service, let key = try storedKey(for: service) else {
      return (settings.translation, nil)
    }
    let agent = ModelTranscriptAgent(service: service, key: key, client: client, gate: gate, parallelism: parallelism)
    return (settings.translation, agent)
  }

  private func storedKey(for service: ModelService) throws(HostError) -> String? {
    do {
      return Self.cleaned(try keys?.key(for: service))
    } catch {
      throw .storage("Keychain (\(error.status))")
    }
  }

  private static func cleaned(_ key: String?) -> String? {
    guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
    return key
  }
}

extension LocalHost: ModelSettingsAccess {
  public func modelSettingsAccess() async -> (any ModelSettingsAccess)? { self }

  public func readModelSettings() async throws(HostError) -> ModelSettingsState {
    try await library.context.models.read()
  }

  public func saveModelSettings(_ settings: ModelSettings, key: ModelKeyChange)
    async throws(HostError) -> ModelSettingsState
  {
    let previous = try? store.modelSettings().service
    let saved = try await library.context.models.save(settings, key: key)
    if previous != saved.settings.service, let runtime = agents.savedRuntime, runtime.provider == .bundledPi {
      _ = try attempt {
        try store.changeSettings { $0.runtime = Runtime(provider: .bundledPi, effort: runtime.effort) }
      }
    }
    if saved.hasKey, environment.bundledPi != nil, agents.savedRuntime == nil,
      await agents.chosen().provider == .bundledPi
    {
      _ = try attempt { try store.changeSettings { $0.runtime = $0.runtime ?? Runtime(provider: .bundledPi) } }
    }
    await provisionPiIfSelected(retry: true)
    await hub.refresh([.everything])
    if saved.hasKey { await library.queue.wake { $0 == .agent } }
    return saved
  }

  public func testModelService(_ service: ModelService, key: String?) async throws(HostError) {
    try await library.context.models.test(service, key: key)
  }

  public func clearTranslationCache() async throws(HostError) {
    try await library.context.models.cache.clear()
  }
}
