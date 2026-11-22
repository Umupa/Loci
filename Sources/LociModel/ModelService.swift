import Foundation

public enum ModelServiceProvider: String, Codable, CaseIterable, Sendable {
  case openAI, anthropic, openRouter, deepSeek, compatible
}

public struct ModelService: Hashable, Codable, Sendable {
  public let provider: ModelServiceProvider
  public let model: String
  public let endpoint: URL

  public init?(provider: ModelServiceProvider, model: String, baseURL: URL? = nil) {
    let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else { return nil }
    let base: URL?
    switch provider {
    case .openAI: base = URL(string: "https://api.openai.com/v1")
    case .anthropic: base = URL(string: "https://api.anthropic.com/v1")
    case .openRouter: base = URL(string: "https://openrouter.ai/api/v1")
    case .deepSeek: base = URL(string: "https://api.deepseek.com")
    case .compatible: base = baseURL
    }
    guard let base, let host = base.host(), !host.isEmpty, base.user() == nil, base.password() == nil,
      base.query() == nil, base.fragment() == nil,
      base.scheme?.lowercased() == "https" || (base.scheme?.lowercased() == "http" && Self.loopback.contains(host))
    else { return nil }
    self.provider = provider
    self.model = model
    let route = provider == .anthropic ? "messages" : "chat/completions"
    if base.path().hasSuffix("/" + route) {
      endpoint = base
    } else {
      endpoint = base.appending(path: route)
    }
  }

  public var baseURL: URL {
    provider == .anthropic
      ? endpoint.deletingLastPathComponent()
      : endpoint.deletingLastPathComponent().deletingLastPathComponent()
  }

  private static let loopback: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

  private enum CodingKeys: String, CodingKey {
    case provider, model, baseURL
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let provider = try values.decode(ModelServiceProvider.self, forKey: .provider)
    let model = try values.decode(String.self, forKey: .model)
    let baseURL = try values.decodeIfPresent(URL.self, forKey: .baseURL)
    guard let service = ModelService(provider: provider, model: model, baseURL: baseURL) else {
      throw DecodingError.dataCorruptedError(forKey: .baseURL, in: values, debugDescription: "Invalid model service")
    }
    self = service
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(provider, forKey: .provider)
    try values.encode(model, forKey: .model)
    if provider == .compatible { try values.encode(baseURL, forKey: .baseURL) }
  }
}
