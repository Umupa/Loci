import Foundation
import LociMedia
import LociModel
import LociStore
import Synchronization
import Testing

@testable import LociHost

/// A host whose model services answer from `TranslationModelNetwork`, with keys in memory and no agents.
func withModelHost(
  keys: MemoryModelKeys = MemoryModelKeys(),
  _ body: (LocalHost, MediaWorld, TranslationModelNetwork, MemoryModelKeys) async throws -> Void
) async throws {
  let world = MediaWorld()
  defer { world.place.remove() }
  try world.install()
  let media = world.environment(transcriber: FakeTranscriber([]), agent: false).media
  let network = TranslationModelNetwork()
  let environment = HostEnvironment(
    newID: { world.world.nextID() }, now: { TestWorld.instant }, defaultRuntime: Runtime(provider: .codex),
    discard: .permanently, agents: { _ in nil }, media: media,
    modelKeys: keys, modelClient: ModelClient(network: network), modelParallelism: 2)
  let host = try await LocalHost.start(
    root: world.place.root, database: world.place.database, environment: environment)
  do {
    try await body(host, world, network, keys)
  } catch {
    await host.close()
    throw error
  }
  await host.close()
}

/// OpenAI with `fixture` checked and used for everything, translating into French, its key saved.
func configureModels(_ host: LocalHost, translation: TranslationSettings = TranslationSettings(language: "fr"))
  async throws -> ModelSettings
{
  var provider = ModelProvider(.openAI)
  provider.models = [ProviderModel(id: "fixture", checked: true)]
  let saved = try await host.saveModelSettings(ModelSettings(providers: [provider], translation: translation))
  _ = try await host.setModelKey("test-key", for: provider.id)
  return saved.settings
}

/// Keys kept in memory, counting how often a key itself is read.
final class MemoryModelKeys: ModelKeyStore {
  private let stored: Mutex<[String: String]>
  private let readings = Mutex(0)

  init(_ keys: [String: String] = [:]) {
    stored = Mutex(keys)
  }

  var reads: Int { readings.withLock { $0 } }

  func key(account: String) -> String? {
    readings.withLock { $0 += 1 }
    return stored.withLock { $0[account] }
  }

  func hasKey(account: String) -> Bool { stored.withLock { $0[account] != nil } }
  func setKey(_ key: String?, account: String) { stored.withLock { $0[account] = key } }
}

/// A model service that translates by prefixing, writes one chapter, picks three key points, lists two models,
/// and answers anything else with OK.
actor TranslationModelNetwork: Network {
  let batches = Latch(open: true)
  private var active = 0
  private(set) var peak = 0
  private(set) var keys: [String] = []
  private(set) var prompts: [String] = []
  private(set) var translationInputs: [[String]] = []

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    if request.httpMethod == "GET", let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    {
      keys.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
      return (Data(#"{"data":[{"id":"fixture"},{"id":"fixture-mini"}]}"#.utf8), response)
    }
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
      let body = request.httpBody,
      let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
      let prompt = (payload["messages"] as? [[String: String]])?.first?["content"]
    else { throw FetchError(reason: "invalid request") }
    keys.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
    prompts.append(prompt)
    let reply: String
    if let start = prompt.range(of: "The input:\n", options: .backwards),
      let inputs = try? JSONDecoder().decode([String: [String]].self, from: Data(prompt[start.upperBound...].utf8)),
      let lines = inputs["lines"]
    {
      translationInputs.append(lines)
      active += 1
      peak = max(peak, active)
      defer { active -= 1 }
      await batches.wait()
      try? await Task.sleep(for: lines.first?.hasPrefix("#") == true ? .milliseconds(110) : .milliseconds(45))
      let json = try? JSONEncoder().encode(["lines": lines.map { "translated " + $0 }])
      reply = String(decoding: json ?? Data(), as: UTF8.self)
    } else if prompt.contains(#"{"chapters":"#) {
      reply = #"{"chapters":[{"start":0,"title":"Model chapter"}]}"#
    } else if prompt.contains(#"{"keyPoints":"#) {
      reply =
        #"{"keyPoints":[{"start":0,"end":1,"title":"First","reason":"A"},"#
        + #"{"start":2,"end":3,"title":"Second","reason":"B"},{"start":4,"end":5,"title":"Third","reason":"C"}]}"#
    } else {
      reply = "OK"
    }
    do {
      let data = try JSONEncoder().encode(["choices": [["message": ["content": reply]]]])
      return (data, response)
    } catch {
      throw FetchError(reason: "could not encode fake reply")
    }
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no downloads")
  }
}
