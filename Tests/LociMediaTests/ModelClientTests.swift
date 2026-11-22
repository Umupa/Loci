import Foundation
import LociModel
import Testing

@testable import LociMedia

struct ModelClientTests {
  @Test(arguments: ModelServiceProvider.allCases)
  func aProbeUsesTheSelectedProvidersEndpointAndProtocol(provider: ModelServiceProvider) async throws {
    let endpoint = URL(string: "https://models.example.test/v1")
    let service = try #require(ModelService(provider: provider, model: "test-model", baseURL: endpoint))
    let network = ModelNetwork()
    let client = ModelClient(network: network)
    try await client.test(service, key: "test-key")
    let requests = await network.requests
    let request = try #require(requests.first)
    let host: String =
      switch provider {
      case .openAI: "api.openai.com"
      case .anthropic: "api.anthropic.com"
      case .openRouter: "openrouter.ai"
      case .deepSeek: "api.deepseek.com"
      case .compatible: "models.example.test"
      }
    #expect(request.url?.host() == host)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path().hasSuffix(provider == .anthropic ? "/messages" : "/chat/completions") == true)
    #expect(request.value(forHTTPHeaderField: "x-api-key") == (provider == .anthropic ? "test-key" : nil))
    #expect(request.value(forHTTPHeaderField: "Authorization") == (provider == .anthropic ? nil : "Bearer test-key"))
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == (provider == .anthropic ? "2023-06-01" : nil))
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "test-model")
    #expect(json["max_tokens"] as? Int == (provider == .anthropic ? 8192 : nil))
  }

  @Test func aFailedResponseDoesNotExposeTheProviderBody() async throws {
    let network = ModelNetwork(status: 401)
    let client = ModelClient(network: network)
    let service = try #require(ModelService(provider: .openAI, model: "test-model"))
    await #expect(throws: FetchError(reason: "HTTP 401", needsLogin: true)) {
      try await client.test(service, key: "test-key")
    }
  }
}

private actor ModelNetwork: Network {
  let status: Int
  var requests: [URLRequest] = []

  init(status: Int = 200) {
    self.status = status
  }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    else { throw FetchError(reason: "missing URL") }
    let body =
      request.value(forHTTPHeaderField: "x-api-key") == nil
      ? #"{"choices":[{"message":{"content":"OK"}}]}"#
      : #"{"content":[{"type":"thinking"},{"type":"text","text":"OK"}]}"#
    return (Data(body.utf8), response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no downloads")
  }
}
