import Foundation
import LociModel

extension Store {
  static let modelSettingsFile = "model-settings.json"

  /// The model services; a file from before there could be several providers is rewritten on first read,
  /// its one service becoming a provider that keeps its key where it was.
  public func modelSettings() throws -> ModelSettings {
    let file = root.appending(path: Self.modelSettingsFile)
    do {
      return try decodeJSON(ModelSettings.self, at: file)
    } catch StoreError.notFound {
      return ModelSettings()
    } catch {
      let old = try decodeJSON(OldModelSettings.self, at: file)
      let settings = old.settings
      try saveModelSettings(settings)
      return settings
    }
  }

  public func saveModelSettings(_ settings: ModelSettings) throws {
    try write(Formats.document(settings), to: root.appending(path: Self.modelSettingsFile))
  }
}

/// `model-settings.json` as versions up to 1.7.10 wrote it: one service and the translation settings.
private struct OldModelSettings: Decodable {
  struct Service: Decodable {
    let provider: String
    let model: String
    let baseURL: URL?
  }

  let service: Service?
  let translation: TranslationSettings?

  var settings: ModelSettings {
    var settings = ModelSettings(translation: translation ?? TranslationSettings())
    guard let service, let provider = Self.provider(service) else { return settings }
    settings.providers = [provider]
    settings.fillToolModel()
    return settings
  }

  private static func provider(_ service: Service) -> ModelProvider? {
    let preset: ModelPreset
    let base: URL?
    switch service.provider {
    case "openAI": (preset, base) = (.openAI, URL(string: "https://api.openai.com/v1"))
    case "anthropic": (preset, base) = (.anthropic, URL(string: "https://api.anthropic.com/v1"))
    case "openRouter": (preset, base) = (.openRouter, URL(string: "https://openrouter.ai/api/v1"))
    case "deepSeek": (preset, base) = (.deepSeek, URL(string: "https://api.deepseek.com"))
    case "compatible": (preset, base) = (.custom, service.baseURL)
    default: return nil
    }
    let model = service.model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty, let base, let address = preset.address ?? ModelAddress(base) else { return nil }
    let route = preset == .anthropic ? "messages" : "chat/completions"
    let endpoint = base.path().hasSuffix("/" + route) ? base : base.appending(path: route)
    return ModelProvider(
      id: ModelProviderID(preset), preset: preset, api: preset.api, address: address,
      keyAccount: service.provider + ":" + endpoint.absoluteString, models: [ProviderModel(id: model, checked: true)])
  }
}
