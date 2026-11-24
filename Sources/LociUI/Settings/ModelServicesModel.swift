import LociModel
import SwiftUI

/// The model services as the settings page holds them: every change shows at once and is saved right after,
/// one save at a time, so there is nothing to save by hand.
@MainActor
@Observable
final class ModelServicesModel {
  /// How trying a provider, or one model on it, went.
  enum Trial: Equatable {
    case running
    case took(Duration)
    case failed(String)
  }

  struct TrialKey: Hashable {
    let provider: ModelProviderID
    let model: String?
  }

  private(set) var state: ModelSettingsState?
  private(set) var failure: LocalizedStringResource?
  private(set) var fetching: Set<ModelProviderID> = []
  private(set) var trials: [TrialKey: Trial] = [:]
  private var latest: [ModelProviderID: TrialKey] = [:]
  /// The provider whose key was saved last, for its tick to be drawn.
  private(set) var keySaved: ModelProviderID?
  private let access: any ModelSettingsAccess
  private var saving: Task<Void, Never>?
  private var edits = 0

  init(access: any ModelSettingsAccess) {
    self.access = access
  }

  var settings: ModelSettings { state?.settings ?? ModelSettings() }

  /// The models the menus offer: checked ones on providers that are on and have a key.
  var groups: [ModelGroup] {
    let keys = state?.keys ?? []
    return settings.groups.filter { keys.contains($0.provider) }
  }

  /// How trying the provider, or a model on it, went last.
  func latestTrial(of provider: ModelProviderID) -> Trial? {
    latest[provider].flatMap { trials[$0] }
  }

  func hasKey(_ provider: ModelProviderID) -> Bool { state?.keys.contains(provider) ?? false }

  func load() async {
    do throws(HostError) {
      state = try await access.readModelSettings()
    } catch {
      failure = Messages.describe(error)
    }
  }

  /// Shows `edit` at once and saves it after the saves before it.
  func change(_ edit: (inout ModelSettings) -> Void) {
    guard let state else { return }
    var settings = state.settings
    edit(&settings)
    guard settings != state.settings else { return }
    self.state = ModelSettingsState(settings: settings, keys: state.keys, cacheBytes: state.cacheBytes)
    edits += 1
    let edit = edits
    let before = saving
    saving = Task {
      await before?.value
      do throws(HostError) {
        let saved = try await access.saveModelSettings(settings)
        if edit == edits { self.state = saved }
      } catch {
        failure = Messages.describe(error)
      }
    }
  }

  func change(_ provider: ModelProviderID, _ edit: @escaping (inout ModelProvider) -> Void) {
    change { settings in
      guard let index = settings.providers.firstIndex(where: { $0.id == provider }) else { return }
      edit(&settings.providers[index])
    }
  }

  func add(_ preset: ModelPreset) -> ModelProviderID {
    let provider = preset == .custom ? ModelProvider(custom: EntityID(), api: .openAI) : ModelProvider(preset)
    change { $0.providers.append(provider) }
    return provider.id
  }

  func remove(_ provider: ModelProviderID) {
    change { $0.providers.removeAll { $0.id == provider } }
  }

  /// Saves the key, or removes it when it is empty; `true` once it is saved.
  @discardableResult
  func setKey(_ key: String, for provider: ModelProviderID) async -> Bool {
    await saving?.value
    let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
    do throws(HostError) {
      state = try await access.setModelKey(value.isEmpty ? nil : value, for: provider)
      keySaved = value.isEmpty ? nil : provider
      return true
    } catch {
      failure = Messages.describe(error)
      return false
    }
  }

  func key(for provider: ModelProviderID) async -> String? {
    do throws(HostError) {
      return try await access.modelKey(for: provider)
    } catch {
      failure = Messages.describe(error)
      return nil
    }
  }

  func fetch(_ provider: ModelProviderID) async {
    await saving?.value
    fetching.insert(provider)
    defer { fetching.remove(provider) }
    do throws(HostError) {
      state = try await access.fetchModels(for: provider)
      latest[provider] = nil
    } catch {
      let key = TrialKey(provider: provider, model: nil)
      trials[key] = .failed(Self.reason(error))
      latest[provider] = key
    }
  }

  func test(_ provider: ModelProviderID, model: String? = nil) async {
    await saving?.value
    let key = TrialKey(provider: provider, model: model)
    trials[key] = .running
    latest[provider] = key
    do throws(HostError) {
      trials[key] = .took(try await access.testModel(model, on: provider))
    } catch {
      trials[key] = .failed(Self.reason(error))
    }
  }

  func clearCache() async {
    do throws(HostError) {
      try await access.clearTranslationCache()
      state = try await access.readModelSettings()
    } catch {
      failure = Messages.describe(error)
    }
  }

  private static func reason(_ error: HostError) -> String {
    switch error {
    case .invalidRequest(let reason), .storage(let reason): reason
    case .notFound(let what): what
    case .alreadyExists, .invalidFile, .offline: String(localized: Messages.describe(error))
    }
  }
}
