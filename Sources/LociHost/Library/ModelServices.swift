import Foundation
import LociMedia
import LociModel
import LociStore

/// The model services on this Mac: the settings, the providers' keys, and asking the models. Whether a key is
/// saved is told without reading it; a key is read only for a request, once, and kept for the rest of the run.
actor ModelServices {
  let gate: Gate
  let parallelism: Int
  let cache: TranslationCache
  private let store: Store
  private let keys: (any ModelKeyStore)?
  private let client: ModelClient
  private let writer: (@Sendable (ModelService) -> any TranscriptAgent)?
  private var known: [String: String] = [:]
  private var piCredentialRevision = 0

  init(store: Store, environment: HostEnvironment) {
    self.store = store
    keys = environment.modelKeys
    client = environment.modelClient
    writer = environment.modelWriter
    parallelism = environment.modelParallelism
    gate = Gate(limit: parallelism)
    cache = TranslationCache(store: store)
  }

  func configuration() throws(HostError) -> ModelSettings {
    try attempt { try store.modelSettings() }
  }

  func read() async throws(HostError) -> ModelSettingsState {
    state(try configuration(), bytes: await cache.bytes())
  }

  func save(_ settings: ModelSettings) async throws(HostError) -> ModelSettingsState {
    var settings = settings
    settings.fillUses()
    try attempt { try store.saveModelSettings(settings) }
    return state(settings, bytes: await cache.bytes())
  }

  func setKey(_ key: String?, for id: ModelProviderID) async throws(HostError) -> ModelSettingsState {
    let settings = try configuration()
    let provider = try Self.provider(id, in: settings)
    guard let keys else { throw .invalidRequest("Keys cannot be saved on this Mac.") }
    let value = Self.cleaned(key)
    do {
      try keys.setKey(value, account: provider.keyAccount)
    } catch {
      throw .storage("Keychain (\(error.status))")
    }
    known[provider.keyAccount] = value
    piCredentialRevision += 1
    return state(settings, bytes: await cache.bytes())
  }

  func key(for id: ModelProviderID) throws(HostError) -> String? {
    try storedKey(account: try Self.provider(id, in: try configuration()).keyAccount)
  }

  func fetchModels(for id: ModelProviderID) async throws(HostError) -> ModelSettingsState {
    let provider = try Self.provider(id, in: try configuration())
    let (address, key) = try request(on: provider)
    let client = client
    let found = try await gate.through { () async throws(HostError) in
      do throws(FetchError) {
        return try await client.models(api: provider.api, at: address, key: key)
      } catch {
        throw .invalidRequest(error.reason)
      }
    }
    var settings = try configuration()
    guard let index = settings.providers.firstIndex(where: { $0.id == id }) else { throw .notFound(id.rawValue) }
    settings.providers[index].offer(found)
    return try await save(settings)
  }

  func test(_ model: String?, on id: ModelProviderID) async throws(HostError) -> Duration {
    let provider = try Self.provider(id, in: try configuration())
    let (address, key) = try request(on: provider)
    guard let model = model ?? provider.checkedModels.first ?? provider.models.first?.id else {
      throw .invalidRequest("Add a model first.")
    }
    let service = ModelService(on: provider, at: address, model: model)
    let client = client
    return try await gate.through { () async throws(HostError) in
      do throws(FetchError) {
        return try await client.test(service, key: key)
      } catch {
        throw .invalidRequest(error.reason)
      }
    }
  }

  /// The models the menus offer: checked ones on providers that are on and have a key.
  func options() throws(HostError) -> ModelOptions {
    let settings = try configuration()
    let saved = state(settings, bytes: 0).keys
    return ModelOptions(groups: settings.groups.filter { saved.contains($0.provider) }, uses: settings.uses)
  }

  /// What `use` is done with, preferring `choice`; `nil` when the model services are not configured for it.
  func work(preferring choice: ModelChoice?, for use: ModelUse) throws(HostError)
    -> (settings: TranslationSettings, service: ModelService, agent: any TranscriptAgent)?
  {
    let settings = try configuration()
    guard let chosen = try options().model(preferring: choice, for: use), let service = settings.service(for: chosen),
      let key = try storedKey(account: service.keyAccount)
    else { return nil }
    let agent =
      writer?(service)
      ?? ModelTranscriptAgent(service: service, key: key, client: client, gate: gate, parallelism: parallelism)
    return (settings.translation, service, agent)
  }

  struct PiCredential: Sendable {
    let service: ModelService
    let key: String?
    let revision: Int
  }

  /// The model the companion runs on with the bundled Pi: the one `runtime` names, else the first offered.
  func piCredential(for runtime: Runtime) throws(HostError) -> PiCredential? {
    let settings = try configuration()
    let offered = try options().groups.flatMap { $0.choices() }
    let named = runtime.model.flatMap(ModelChoice.init(runtimeModel:))
    guard let chosen = offered.first(where: { $0 == named }) ?? offered.first,
      let service = settings.service(for: chosen)
    else { return nil }
    return PiCredential(
      service: service, key: try storedKey(account: service.keyAccount), revision: piCredentialRevision)
  }

  private func state(_ settings: ModelSettings, bytes: Int64) -> ModelSettingsState {
    let saved = settings.providers.filter { provider in
      if known[provider.keyAccount] != nil { return true }
      return (try? keys?.hasKey(account: provider.keyAccount)) ?? false
    }
    return ModelSettingsState(settings: settings, keys: Set(saved.map(\.id)), cacheBytes: bytes)
  }

  private func request(on provider: ModelProvider) throws(HostError) -> (ModelAddress, String) {
    guard let address = provider.address else { throw .invalidRequest("Enter the provider's address.") }
    guard let key = try storedKey(account: provider.keyAccount) else { throw .invalidRequest("Enter an API key.") }
    return (address, key)
  }

  private func storedKey(account: String) throws(HostError) -> String? {
    if let key = known[account] { return key }
    let key: String?
    do {
      key = Self.cleaned(try keys?.key(account: account))
    } catch {
      throw .storage("The keychain did not let Loci read the key (\(error.status)).")
    }
    known[account] = key
    return key
  }

  private static func provider(_ id: ModelProviderID, in settings: ModelSettings) throws(HostError) -> ModelProvider {
    guard let provider = settings.providers.first(where: { $0.id == id }) else { throw .notFound(id.rawValue) }
    return provider
  }

  private static func cleaned(_ key: String?) -> String? {
    guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
    return key
  }
}
