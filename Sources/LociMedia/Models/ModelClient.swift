import Foundation
import LociModel

public struct ModelClient: Sendable {
  private static let systemNetwork = SystemNetwork(
    session: URLSession(configuration: .ephemeral, delegate: ModelRedirects(), delegateQueue: nil))

  private let network: any Network

  public init() {
    network = Self.systemNetwork
  }

  public init(network: any Network) {
    self.network = network
  }

  public func test(_ service: ModelService, key: String) async throws(FetchError) {
    _ = try await answer("Reply with OK.", using: service, key: key, timeout: 15)
  }

  public func answer(_ prompt: String, using service: ModelService, key: String, timeout: TimeInterval = 120)
    async throws(FetchError) -> String
  {
    var request = URLRequest(url: service.endpoint, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let anthropic = service.provider == .anthropic
    if anthropic {
      request.setValue(key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    } else {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    do {
      request.httpBody = try JSONEncoder().encode(
        Request(
          model: service.model, messages: [Message(role: "user", content: prompt)],
          maxTokens: anthropic ? 8192 : nil))
    } catch {
      throw FetchError(reason: "The model request could not be encoded.")
    }
    let (data, response) = try await network.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw FetchError(reason: "HTTP \(response.statusCode)", needsLogin: [401, 403].contains(response.statusCode))
    }
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
