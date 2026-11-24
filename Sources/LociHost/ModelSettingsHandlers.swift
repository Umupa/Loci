import Foundation
import LociModel
import LociStore

extension LocalHost: ModelSettingsAccess {
  public func modelSettingsAccess() async -> (any ModelSettingsAccess)? { self }

  public func readModelSettings() async throws(HostError) -> ModelSettingsState {
    try await library.context.models.read()
  }

  public func saveModelSettings(_ settings: ModelSettings) async throws(HostError) -> ModelSettingsState {
    let saved = try await library.context.models.save(settings)
    await modelsChanged()
    return saved
  }

  public func setModelKey(_ key: String?, for provider: ModelProviderID) async throws(HostError)
    -> ModelSettingsState
  {
    let saved = try await library.context.models.setKey(key, for: provider)
    await modelsChanged()
    return saved
  }

  public func modelKey(for provider: ModelProviderID) async throws(HostError) -> String? {
    try await library.context.models.key(for: provider)
  }

  public func fetchModels(for provider: ModelProviderID) async throws(HostError) -> ModelSettingsState {
    let saved = try await library.context.models.fetchModels(for: provider)
    await modelsChanged()
    return saved
  }

  public func testModel(_ model: String?, on provider: ModelProviderID) async throws(HostError) -> Duration {
    try await library.context.models.test(model, on: provider)
  }

  public func clearTranslationCache() async throws(HostError) {
    try await library.context.models.cache.clear()
  }

  public func modelOptions() async throws(HostError) -> ModelOptions {
    try await library.context.models.options()
  }

  /// Once there is a model to use: the bundled Pi becomes the companion's runtime when nothing else was
  /// chosen and no CLI is installed, and what waited for the model services goes on.
  private func modelsChanged() async {
    let offered = !((try? await library.context.models.options().groups.isEmpty) ?? true)
    if offered, environment.bundledPi != nil, agents.savedRuntime == nil,
      await agents.chosen().provider == .bundledPi
    {
      _ = try? attempt { try store.changeSettings { $0.runtime = $0.runtime ?? Runtime(provider: .bundledPi) } }
    }
    await provisionPiIfSelected(retry: true)
    await hub.refresh([.everything])
    if offered { await library.queue.wake { $0 == .modelService } }
  }
}
