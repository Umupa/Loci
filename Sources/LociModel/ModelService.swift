import Foundation

/// One model on one provider, ready to be asked: where to send requests and which key to send them with.
/// Only `ModelSettings` makes one, from a provider that is on and a model checked on it.
public struct ModelService: Hashable, Sendable {
  public let provider: ModelProviderID
  public let preset: ModelPreset
  public let api: ModelAPI
  public let address: ModelAddress
  public let model: String
  public let keyAccount: String

  init?(_ provider: ModelProvider, model: String) {
    guard provider.enabled, let address = provider.address, provider.checkedModels.contains(model) else {
      return nil
    }
    self.init(on: provider, at: address, model: model)
  }

  /// The provider at `address`, asked with `model` whether or not it is checked: for trying a provider out.
  public init(on provider: ModelProvider, at address: ModelAddress, model: String) {
    self.provider = provider.id
    preset = provider.preset
    api = provider.api
    self.address = address
    self.model = model
    keyAccount = provider.keyAccount
  }

  public var choice: ModelChoice { ModelChoice(provider: provider, model: model) }

  /// Where a request for an answer goes.
  public var endpoint: URL {
    api.route(api == .anthropic ? "messages" : "chat/completions", at: address)
  }

  /// Where the provider lists its models.
  public var models: URL { api.route("models", at: address) }
}
