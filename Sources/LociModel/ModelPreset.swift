import Foundation

/// How a provider is spoken to.
public enum ModelAPI: String, Codable, CaseIterable, Sendable {
  /// `POST {address}/chat/completions` and `GET {address}/models` with a bearer key.
  case openAI
  /// `POST {address}/v1/messages` and `GET {address}/v1/models` with `x-api-key`.
  case anthropic

  /// Where `path` is on a provider at `address`.
  public func route(_ path: String, at address: ModelAddress) -> URL {
    let base = address.url
    guard self == .anthropic else { return base.appending(path: path) }
    let versioned = base.path().split(separator: "/").last == "v1"
    return versioned ? base.appending(path: path) : base.appending(path: "v1").appending(path: path)
  }
}

/// The providers Loci knows the address of, and one of your own.
public enum ModelPreset: String, Codable, CaseIterable, Sendable {
  case openAI, anthropic, openRouter, deepSeek, kimi, zhipu, qwen, siliconFlow, volcengine, miniMax, custom

  public var api: ModelAPI { self == .anthropic ? .anthropic : .openAI }

  /// The address in the provider's own documentation; `nil` for one of your own.
  public var address: ModelAddress? {
    switch self {
    case .openAI: ModelAddress("https://api.openai.com/v1")
    case .anthropic: ModelAddress("https://api.anthropic.com")
    case .openRouter: ModelAddress("https://openrouter.ai/api/v1")
    case .deepSeek: ModelAddress("https://api.deepseek.com")
    case .kimi: ModelAddress("https://api.moonshot.cn/v1")
    case .zhipu: ModelAddress("https://open.bigmodel.cn/api/paas/v4")
    case .qwen: ModelAddress("https://dashscope.aliyuncs.com/compatible-mode/v1")
    case .siliconFlow: ModelAddress("https://api.siliconflow.cn/v1")
    case .volcengine: ModelAddress("https://ark.cn-beijing.volces.com/api/v3")
    case .miniMax: ModelAddress("https://api.minimax.cn/v1")
    case .custom: nil
    }
  }
}

/// A provider's base address: https, or plain http on this Mac only; never with a user, a query or a fragment.
public struct ModelAddress: Hashable, Sendable {
  public let url: URL

  public init?(_ text: String) {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    self.init(url)
  }

  public init?(_ url: URL) {
    guard let host = url.host(), !host.isEmpty, url.user() == nil, url.password() == nil, url.query() == nil,
      url.fragment() == nil
    else { return nil }
    let scheme = url.scheme?.lowercased()
    guard scheme == "https" || (scheme == "http" && Self.loopback.contains(host)) else { return nil }
    self.url = url
  }

  private static let loopback: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
}

extension ModelAddress: Codable {
  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let address = ModelAddress(text) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid address"))
    }
    self = address
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(url.absoluteString)
  }
}
