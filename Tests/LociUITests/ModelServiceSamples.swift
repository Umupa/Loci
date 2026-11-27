import Foundation
import LociModel
import Synchronization

@testable import LociUI

/// Model settings kept in memory, remembering every save, key and request, for the settings page to work on.
final class SampleModelAccess: ModelSettingsAccess {
  private let held: Mutex<ModelSettingsState>
  private let saved = Mutex<[ModelSettings]>([])
  private let keyed = Mutex<[(String?, ModelProviderID)]>([])

  init(_ state: ModelSettingsState = SampleModelAccess.state) {
    held = Mutex(state)
  }

  var saves: [ModelSettings] { saved.withLock { $0 } }
  var keys: [(String?, ModelProviderID)] { keyed.withLock { $0 } }

  func readModelSettings() async throws(HostError) -> ModelSettingsState { held.withLock { $0 } }

  func saveModelSettings(_ settings: ModelSettings) async throws(HostError) -> ModelSettingsState {
    saved.withLock { $0.append(settings) }
    return held.withLock { state in
      state = ModelSettingsState(settings: settings, keys: state.keys, cacheBytes: state.cacheBytes)
      return state
    }
  }

  func setModelKey(_ key: String?, for provider: ModelProviderID) async throws(HostError) -> ModelSettingsState {
    keyed.withLock { $0.append((key, provider)) }
    return held.withLock { state in
      var keys = state.keys
      if key == nil { keys.remove(provider) } else { keys.insert(provider) }
      state = ModelSettingsState(settings: state.settings, keys: keys, cacheBytes: state.cacheBytes)
      return state
    }
  }

  func modelKey(for provider: ModelProviderID) async throws(HostError) -> String? { "sk-sample" }

  func fetchModels(for provider: ModelProviderID) async throws(HostError) -> ModelSettingsState {
    held.withLock { $0 }
  }

  func testModel(_ model: String?, on provider: ModelProviderID) async throws(HostError) -> Duration {
    .milliseconds(312)
  }

  func clearTranslationCache() async throws(HostError) {}

  /// The design's page: DeepSeek and OpenRouter on with keys, Anthropic and OpenAI off, translation into Chinese.
  static let state: ModelSettingsState = {
    var deepSeek = ModelProvider(.deepSeek)
    deepSeek.models = [
      ProviderModel(id: "deepseek-chat", checked: true), ProviderModel(id: "deepseek-reasoner", checked: false),
    ]
    var openRouter = ModelProvider(.openRouter)
    openRouter.models = [
      ProviderModel(id: "gemini-3-flash", checked: true), ProviderModel(id: "kimi-k3", checked: true),
    ]
    var anthropic = ModelProvider(.anthropic)
    anthropic.enabled = false
    var openAI = ModelProvider(.openAI)
    openAI.enabled = false
    let settings = ModelSettings(
      providers: [deepSeek, openRouter, anthropic, openAI],
      toolModel: ModelChoice(provider: openRouter.id, model: "gemini-3-flash"),
      translation: TranslationSettings(
        model: ModelChoice(provider: deepSeek.id, model: "deepseek-chat"), language: "zh-Hans", smart: true))
    return ModelSettingsState(settings: settings, keys: [deepSeek.id, openRouter.id], cacheBytes: 18_400_000)
  }()

  static let empty = ModelSettingsState(settings: ModelSettings(), keys: [], cacheBytes: 0)
}
