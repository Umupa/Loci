import Foundation

/// Names a provider in the settings: a preset by its own name, one of your own by an identifier.
public struct ModelProviderID: Hashable, Codable, Sendable {
  public let rawValue: String

  public init(_ preset: ModelPreset) {
    rawValue = preset.rawValue
  }

  public init(custom id: EntityID) {
    rawValue = "custom-" + id.description
  }

  public init?(rawValue: String) {
    guard !rawValue.isEmpty, !rawValue.contains("/") else { return nil }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let id = ModelProviderID(rawValue: text) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid provider"))
    }
    self = id
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A model a provider offers, and whether it is one to use.
public struct ProviderModel: Hashable, Codable, Sendable {
  public let id: String
  public var checked: Bool

  public init(id: String, checked: Bool) {
    self.id = id
    self.checked = checked
  }
}

/// One provider in the model services: where it is, the models checked on it, and whether it is on. Its key
/// is in the keychain under `keyAccount`, never in the data folder.
public struct ModelProvider: Hashable, Codable, Sendable, Identifiable {
  public let id: ModelProviderID
  public let preset: ModelPreset
  /// Only one of your own has a name; a preset goes by its own.
  public var name: String
  public var api: ModelAPI
  /// `nil` until one of your own is given an address.
  public var address: ModelAddress?
  public var enabled: Bool
  public var models: [ProviderModel]
  public let keyAccount: String

  /// A preset at its own address, on, with no models yet.
  public init(_ preset: ModelPreset) {
    self.init(
      id: ModelProviderID(preset), preset: preset, api: preset.api, address: preset.address,
      keyAccount: Self.account(ModelProviderID(preset)))
  }

  /// One of your own, without an address yet.
  public init(custom id: EntityID, api: ModelAPI) {
    let provider = ModelProviderID(custom: id)
    self.init(id: provider, preset: .custom, api: api, address: nil, keyAccount: Self.account(provider))
  }

  /// A provider whose key was saved before under `keyAccount`.
  public init(
    id: ModelProviderID, preset: ModelPreset, api: ModelAPI, address: ModelAddress?, keyAccount: String,
    models: [ProviderModel] = []
  ) {
    self.id = id
    self.preset = preset
    name = ""
    self.api = api
    self.address = address
    enabled = true
    self.models = models
    self.keyAccount = keyAccount
  }

  public var checkedModels: [String] { models.filter(\.checked).map(\.id) }

  /// Adds models not on the list yet, unchecked, after the ones there.
  public mutating func offer(_ found: [String]) {
    var known = Set(models.map(\.id))
    models += found.filter { known.insert($0).inserted }.map { ProviderModel(id: $0, checked: false) }
  }

  private static func account(_ id: ModelProviderID) -> String {
    "provider:" + id.rawValue
  }
}

/// A model on a provider: what translation, chapters and key points, or the companion on the bundled Pi, use.
public struct ModelChoice: Hashable, Codable, Sendable {
  public let provider: ModelProviderID
  public let model: String

  public init(provider: ModelProviderID, model: String) {
    self.provider = provider
    self.model = model
  }

  /// How the bundled Pi's runtime names it.
  public var runtimeModel: String { provider.rawValue + "/" + model }

  public init?(runtimeModel: String) {
    guard let slash = runtimeModel.firstIndex(of: "/"),
      let provider = ModelProviderID(rawValue: String(runtimeModel[..<slash]))
    else { return nil }
    let model = String(runtimeModel[runtimeModel.index(after: slash)...])
    guard !model.isEmpty else { return nil }
    self.init(provider: provider, model: model)
  }
}

/// The models on one provider that are on, as the menus list them.
public struct ModelGroup: Hashable, Codable, Sendable {
  public let provider: ModelProviderID
  public let preset: ModelPreset
  /// Only one of your own has a name.
  public let name: String
  public let models: [String]

  public init(provider: ModelProviderID, preset: ModelPreset, name: String, models: [String]) {
    self.provider = provider
    self.preset = preset
    self.name = name
    self.models = models
  }

  public func choices() -> [ModelChoice] {
    models.map { ModelChoice(provider: provider, model: $0) }
  }
}
