import Foundation
import LociModel

extension Store {
  static let modelSettingsFile = "model-settings.json"

  public func modelSettings() throws -> ModelSettings {
    do {
      return try decodeJSON(ModelSettings.self, at: root.appending(path: Self.modelSettingsFile))
    } catch StoreError.notFound {
      return ModelSettings()
    }
  }

  public func saveModelSettings(_ settings: ModelSettings) throws {
    try write(Formats.document(settings), to: root.appending(path: Self.modelSettingsFile))
  }
}
