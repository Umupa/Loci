import Foundation
import LociModel

/// A model pinned into the flyout's Favorites tab.
struct FavoriteModel: Codable, Hashable {
  let provider: Provider
  let id: String
  let name: String
}

/// Persists favorite models for the model flyout in user defaults.
@Observable
@MainActor
final class ModelFavorites {
  static let shared = ModelFavorites()

  private let defaults: UserDefaults
  private let storageKey = "loci.favoriteModels.v1"
  private(set) var items: [FavoriteModel]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([FavoriteModel].self, from: data)
    {
      self.items = decoded
    } else {
      self.items = []
    }
  }

  func contains(provider: Provider, model: String) -> Bool {
    items.contains { $0.provider == provider && $0.id == model }
  }

  func toggle(provider: Provider, model: String, name: String) {
    if let index = items.firstIndex(where: { $0.provider == provider && $0.id == model }) {
      items.remove(at: index)
    } else {
      items.append(FavoriteModel(provider: provider, id: model, name: name))
    }
    if let data = try? JSONEncoder().encode(items) {
      defaults.set(data, forKey: storageKey)
    }
  }
}
