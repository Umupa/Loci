import Foundation
import LociModel

/// Asks a model service for answers and lists its models, sending the key only to the provider's own address.
public struct ModelClient: Sendable {
  private static let systemNetwork = SystemNetwork(
    session: URLSession(configuration: .ephemeral, delegate: ModelRedirects(), delegateQueue: nil))
  /// The moment the default clock counts from.
  public static let origin = ContinuousClock.now

  let network: any Network
  private let clock: @Sendable () -> Duration

  public init() {
    self.init(network: Self.systemNetwork)
  }

  /// `clock` tells the time that has passed since any fixed moment.
  public init(network: any Network, clock: @escaping @Sendable () -> Duration = { origin.duration(to: .now) }) {
    self.network = network
    self.clock = clock
  }

  /// Asks for a short answer and says how long it took.
  public func test(_ service: ModelService, key: String) async throws(FetchError) -> Duration {
    let start = clock()
    _ = try await answer("Reply with OK.", using: service, key: key, timeout: 15)
    return clock() - start
  }

  public func answer(_ prompt: String, using service: ModelService, key: String, timeout: TimeInterval = 120)
    async throws(FetchError) -> String
  {
    var request = Self.request(service.endpoint, api: service.api, key: key, timeout: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let anthropic = service.api == .anthropic
    do {
      request.httpBody = try JSONEncoder().encode(
        Request(
          model: service.model, messages: [Message(role: "user", content: prompt)],
          maxTokens: anthropic ? 8192 : nil))
    } catch {
      throw FetchError(reason: "The model request could not be encoded.")
    }
    let data = try await send(request, key: key)
    let text: String?
    do {
      if anthropic {
        text = try JSONDecoder().decode(MessagesReply.self, from: data).content
          .filter { $0.type == "text" }.compactMap(\.text).joined()
      } else {
        text = try JSONDecoder().decode(ChatReply.self, from: data).choices.first?.message.content
      }
    } catch {
      throw FetchError(reason: "The model service returned an unreadable response.")
    }
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FetchError(reason: "The model service returned no text.")
    }
    return text
  }

  static func request(_ url: URL, api: ModelAPI, key: String, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    if api == .anthropic {
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    } else {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  /// The body of a successful response; a failure says the status and the provider's own message, if any,
  /// with the key taken out.
  func send(_ request: URLRequest, key: String) async throws(FetchError) -> Data {
    let (data, response) = try await network.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      var reason = "HTTP \(response.statusCode)"
      if let message = (try? JSONDecoder().decode(Refusal.self, from: data))?.error.message {
        let shown = message.replacingOccurrences(of: key, with: "…").prefix(200)
        reason += ": " + shown
      }
      throw FetchError(reason: reason, needsLogin: [401, 403].contains(response.statusCode))
    }
    return data
  }

  private struct Refusal: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
  }

  private struct Message: Encodable {
    let role: String
    let content: String
  }

  private struct Request: Encodable {
    let model: String
    let messages: [Message]
    let maxTokens: Int?

    private enum CodingKeys: String, CodingKey {
      case model, messages
      case maxTokens = "max_tokens"
    }
  }

  private struct ChatReply: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable { let content: String? }
      let message: Message
    }

    let choices: [Choice]
  }

  private struct MessagesReply: Decodable {
    struct Block: Decodable {
      let type: String
      let text: String?
    }

    let content: [Block]
  }
}

private final class ModelRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
