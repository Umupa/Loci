import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociMedia

struct ModelClientTests {
  @Test(arguments: ModelAPI.allCases)
  func aProbeUsesTheProvidersEndpointAndProtocol(api: ModelAPI) async throws {
    let network = ModelNetwork()
    let client = ModelClient(network: network)
    _ = try await client.answer("Reply with OK.", using: try service(api), key: "test-key")
    let request = try #require(await network.requests.first)
    #expect(request.url?.host() == "models.example.test")
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path() == (api == .anthropic ? "/base/v1/messages" : "/base/chat/completions"))
    #expect(request.value(forHTTPHeaderField: "x-api-key") == (api == .anthropic ? "test-key" : nil))
    #expect(request.value(forHTTPHeaderField: "Authorization") == (api == .anthropic ? nil : "Bearer test-key"))
    #expect(request.value(forHTTPHeaderField: "anthropic-version") == (api == .anthropic ? "2023-06-01" : nil))
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "test-model")
    #expect(json["max_tokens"] as? Int == (api == .anthropic ? 8192 : nil))
  }

  @Test func aTestSaysHowLongTheAnswerTook() async throws {
    let clock = ModelTestClock()
    let network = ModelNetwork(answering: { clock.advance(by: .milliseconds(312)) })
    let client = ModelClient(network: network, clock: { clock.now })
    #expect(try await client.test(try service(.openAI), key: "test-key") == .milliseconds(312))
  }

  @Test func aFailedRequestSaysTheStatusAndTheServicesMessageWithoutTheKey() async throws {
    let network = ModelNetwork(
      status: 400, body: #"{"error":{"message":"Model deepseek-x does not exist for key test-key"}}"#)
    let client = ModelClient(network: network)
    await #expect(throws: FetchError(reason: "HTTP 400: Model deepseek-x does not exist for key …")) {
      try await client.test(try service(.openAI), key: "test-key")
    }
    let refused = ModelClient(network: ModelNetwork(status: 401, body: "<html>no</html>"))
    await #expect(throws: FetchError(reason: "HTTP 401", needsLogin: true)) {
      try await refused.test(try service(.openAI), key: "test-key")
    }
  }

  @Test func listingModelsOnAnOpenAICompatibleServiceReadsTheirIds() async throws {
    let network = ModelNetwork(body: #"{"object":"list","data":[{"id":"deepseek-chat"},{"id":"deepseek-reasoner"}]}"#)
    let client = ModelClient(network: network)
    let address = try #require(ModelAddress("https://api.deepseek.com"))
    #expect(try await client.models(api: .openAI, at: address, key: "k") == ["deepseek-chat", "deepseek-reasoner"])
    let request = try #require(await network.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://api.deepseek.com/models")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
  }

  @Test func listingAnthropicModelsSendsTheKeyAndVersionAndFollowsPages() async throws {
    let network = ModelNetwork(pages: [
      #"{"data":[{"id":"claude-a","display_name":"A"}],"has_more":true,"last_id":"claude-a"}"#,
      #"{"data":[{"id":"claude-b","display_name":"B"}],"has_more":false,"last_id":"claude-b"}"#,
    ])
    let client = ModelClient(network: network)
    let address = try #require(ModelAddress("https://api.anthropic.com"))
    #expect(try await client.models(api: .anthropic, at: address, key: "k") == ["claude-a", "claude-b"])
    let requests = await network.requests
    #expect(
      requests.map { $0.url?.absoluteString } == [
        "https://api.anthropic.com/v1/models?limit=1000",
        "https://api.anthropic.com/v1/models?limit=1000&after_id=claude-a",
      ])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-api-key") == "k" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" })
  }

  private func service(_ api: ModelAPI) throws -> ModelService {
    var provider = ModelProvider(custom: EntityID(), api: api)
    provider.address = ModelAddress("https://models.example.test/base")
    return ModelService(on: provider, at: try #require(provider.address), model: "test-model")
  }
}

private actor ModelNetwork: Network {
  let status: Int
  var pages: [String]
  let answering: @Sendable () -> Void
  var requests: [URLRequest] = []

  init(status: Int = 200, body: String? = nil, pages: [String] = [], answering: @escaping @Sendable () -> Void = {}) {
    self.status = status
    self.pages = body.map { [$0] } ?? pages
    self.answering = answering
  }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    requests.append(request)
    answering()
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    else { throw FetchError(reason: "missing URL") }
    if !pages.isEmpty { return (Data(pages.removeFirst().utf8), response) }
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

private final class ModelTestClock: Sendable {
  private let elapsed = Mutex(Duration.zero)

  var now: Duration { elapsed.withLock { $0 } }

  func advance(by duration: Duration) {
    elapsed.withLock { $0 += duration }
  }
}
