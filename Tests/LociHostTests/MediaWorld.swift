import Foundation
import LociHost
import LociMedia
import LociModel
import LociStore
import Synchronization
import Testing

/// A temporary Loci folder with fake programs, network, recognition and agent for the library to use.
struct MediaWorld {
  let place = Place()
  let world = TestWorld()
  let programs = FakePrograms()
  let network: FakeNetwork
  let agent = FakeTranscriptAgent()
  /// What each writer was made for, in order.
  let models = ModelLog()
  /// The keys of the model services; `agent` worlds have one for `MediaWorld.service`.
  let keys = MemoryModelKeys()

  init() {
    network = FakeNetwork(folder: place.root.appending(path: ".downloads"))
  }

  var support: URL { place.root.appending(path: ".support") }
  var bin: URL { place.root.appending(path: ".bin") }

  /// Puts components where the host looks for ones already on this Mac.
  func install(_ components: [Component] = Component.allCases) throws {
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    guard !components.isEmpty else { return }
    for component in components where component != .bundledPi {
      let name = ["ytDlp": "yt-dlp", "ffmpeg": "ffmpeg", "quickJS": "qjs"][component.rawValue] ?? ""
      let file = bin.appending(path: name)
      try Data("#!/bin/sh\n".utf8).write(to: file)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
  }

  func installModel(_ model: SpeechModel = .recommended) throws {
    let models = support.appending(path: "models")
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    try Data("ggml".utf8).write(to: models.appending(path: model.fileName))
  }

  func environment(
    transcriber: FakeTranscriber, agent: Bool = true, text: Bool = true, readerLanguage: String = "zh-Hans",
    fetcher: (any TextFetching)? = nil, diarizer: (any Diarizing)? = nil, provider: Provider = .codex
  ) -> HostEnvironment {
    let writer = self.agent
    let models = self.models
    if agent { configureModels() }
    let write: @Sendable (ModelService) -> any TranscriptAgent = { service in
      models.add(service.choice)
      return writer
    }
    var speakers: (@Sendable (Runtime) -> any TranscriptAgent)?
    if agent { speakers = { _ in writer } }
    let media = MediaEnvironment(
      support: support, runner: programs, network: network, transcriber: transcriber, searchPaths: [bin],
      readerLanguage: readerLanguage, textFetching: fetcher ?? (text ? FakeTextFetcher() : nil),
      transcriptAgent: speakers, diarizer: diarizer)
    return HostEnvironment(
      newID: { [world] in world.nextID() }, now: { TestWorld.instant }, defaultRuntime: Runtime(provider: provider),
      discard: .permanently,
      agents: { _ in nil }, media: media, modelKeys: keys, modelParallelism: 1, modelWriter: write)
  }

  /// The model the world's model services translate, write chapters and pick key points with.
  static let model = ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-chat")

  /// DeepSeek, with `MediaWorld.model` and a second checked model, used for everything and its key saved.
  func configureModels() {
    var provider = ModelProvider(.deepSeek)
    provider.models = [
      ProviderModel(id: "deepseek-chat", checked: true), ProviderModel(id: "deepseek-reasoner", checked: true),
    ]
    let settings = ModelSettings(
      providers: [provider], toolModel: Self.model)
    try? place.store.saveModelSettings(settings)
    keys.setKey("test-key", account: provider.keyAccount)
  }

  func start(
    transcriber: FakeTranscriber = FakeTranscriber([]), agent: Bool = true, text: Bool = true,
    readerLanguage: String = "zh-Hans", fetcher: (any TextFetching)? = nil, diarizer: (any Diarizing)? = nil,
    provider: Provider = .codex
  ) async throws -> LocalHost {
    try await LocalHost.start(
      root: place.root, database: place.database,
      environment: environment(
        transcriber: transcriber, agent: agent, text: text, readerLanguage: readerLanguage,
        fetcher: fetcher, diarizer: diarizer, provider: provider))
  }
}

/// Runs `body` against a host over a new media world, then closes the host and deletes the world.
func withMediaHost(
  transcriber: FakeTranscriber = FakeTranscriber([]), agent: Bool = true, text: Bool = true,
  components: [Component] = Component.allCases, readerLanguage: String = "zh-Hans",
  _ body: (LocalHost, MediaWorld) async throws -> Void
) async throws {
  let world = MediaWorld()
  defer { world.place.remove() }
  try world.install(components)
  let host = try await world.start(
    transcriber: transcriber, agent: agent, text: text, readerLanguage: readerLanguage)
  do {
    try await body(host, world)
  } catch {
    await host.close()
    throw error
  }
  await host.close()
}

/// The job once it reaches a state `match` accepts, or `nil` if it does not within `patience`.
func job(_ host: LocalHost, _ item: EntityID, where match: @escaping @Sendable (Job?) -> Bool) async -> Job?? {
  let feed = host.subscribe(ItemJob(item: item))
  let found = await first(feed) { delivered in
    if case .value(let job) = delivered { return match(job) }
    return false
  }
  guard case .value(let job) = found else { return nil }
  return .some(job)
}

func isDone(_ job: Job?) -> Bool { job == nil }

func state(_ expected: Job.State) -> @Sendable (Job?) -> Bool {
  { $0?.state == expected }
}

func isRunning(_ stage: Job.Stage) -> @Sendable (Job?) -> Bool {
  { job in
    guard let job, job.stage == stage, case .running = job.state else { return false }
    return true
  }
}

enum Links {
  static let youtube = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
  static let bilibili = "https://www.bilibili.com/video/BV1GJ411x7h7"
  static let episode = "https://podcasts.apple.com/us/podcast/x/id1200361736?i=1000802251165"
  static let article = "https://queue.acm.org/detail.cfm?id=2898444"
  static let paper = "https://arxiv.org/abs/1234.5678"

  static func url(_ link: String) -> URL { URL(string: link)! }
}

let zooSubtitles = """
  WEBVTT

  00:00:01.000 --> 00:00:04.000
  All right, so here we are in front of the elephants

  00:00:04.000 --> 00:00:08.000
  the cool thing about these guys is that they have really long trunks
  """

let spoken: [Heard] = [
  .language("en"),
  FakeTranscriber.words("The scheduler filters nodes.", from: 0),
  .progress(Fraction(0.4)),
  FakeTranscriber.words("Then it scores them.", from: 2),
  .progress(Fraction(0.8)),
  FakeTranscriber.words("Finally it binds the pod.", from: 4),
  .progress(Fraction(1)),
]

/// The models writers were made for.
final class ModelLog: Sendable {
  private let made = Mutex<[ModelChoice]>([])

  var all: [ModelChoice] { made.withLock { $0 } }

  func add(_ model: ModelChoice) {
    made.withLock { $0.append(model) }
  }
}
