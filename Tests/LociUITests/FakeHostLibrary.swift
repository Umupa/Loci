import Foundation
import LociModel

/// The library's commands, answered with nothing in progress and nothing installed.
extension FakeHost {
  /// A link in the library is that item; one of the sample links is read at once; any other is never read.
  func probeLink(_ command: ProbeLink) async throws(HostError) -> LinkProbe {
    if let saved = (library?.items ?? []).first(where: { $0.source == command.url }) { return .saved(saved) }
    if let media = ImportSamples.previews[command.url] { return .media(media) }
    try? await Task.sleep(for: .seconds(600))
    throw .notFound(command.url.absoluteString)
  }

  func importChoice() async throws(HostError) -> ImportChoice {
    lastChoice ?? .first(readerLanguage: "zh-Hans", speechModel: .largeV3Turbo)
  }

  func addLink(_ command: AddLink) async throws(HostError) -> Item { sample.items[0] }
  func importMediaFile(_ command: ImportMediaFile) async throws(HostError) -> Item { sample.items[0] }

  func retryJob(_ item: EntityID) async throws(HostError) -> Job {
    Job(item: item, stage: .resolve, state: .queued)
  }

  func savingBatch() async -> SavingBatch? { library?.saving }
  func stopSaving() async throws(HostError) -> Int { 0 }
  func storage() async throws(HostError) -> StorageReport {
    library?.storage ?? StorageReport(capacity: nil, available: nil, items: [], speechModels: [])
  }
  func freeMediaSpace(_ item: EntityID) async throws(HostError) -> Done { Done() }
  func saveMediaLocally(_ item: EntityID) async throws(HostError) -> Job {
    Job(item: item, stage: .download, state: .queued)
  }
  func pauseJob(_ item: EntityID) async throws(HostError) -> Done { Done() }
  func translateArticle(_ item: EntityID) async throws(HostError) -> Done { Done() }
  func pickKeyPoints(_ command: PickKeyPoints) async throws(HostError) -> Done { Done() }

  func keyPointsPage(_ item: EntityID) async throws(HostError) -> KeyPointsPage {
    let choice = KeyPointChoice(runtime: Runtime(provider: .codex, model: "gpt-5.2"), count: .some)
    switch keyPoints {
    case .none: return KeyPointsPage(keyPoints: nil, picking: nil, choice: choice)
    case .picking: return KeyPointsPage(keyPoints: nil, picking: .running, choice: choice)
    case .picked: return KeyPointsPage(keyPoints: try? library?.keyPoints(of: item), picking: nil, choice: choice)
    }
  }
  func jobs() async throws(HostError) -> [Job] { (library?.jobs ?? []) + (recognizing ? [recognition] : []) }

  func job(of item: EntityID) async throws(HostError) -> Job? {
    try await jobs().first { $0.item == item }
  }

  private var recognition: Job {
    Job(item: library?.video.id ?? sample.borg.id, stage: .transcribe, state: .running(progress: Fraction(0.63)))
  }

  func mediaPage(_ item: EntityID) async throws(HostError) -> MediaPage {
    if let library {
      if item == library.video.id, let page = try? library.videoPage(recognizing: recognizing) { return page }
      if item == library.podcast.id, let page = try? library.podcastPage() { return page }
    }
    return MediaPage(transcript: nil, translations: [], outline: nil, hasCover: false, downloaded: false)
  }

  func playback(_ command: ReadPlayback) async throws(HostError) -> Playback {
    throw .notFound("media of \(command.item)")
  }

  func mediaFileInfo(of item: EntityID) async throws(HostError) -> MediaFileInfo {
    throw .notFound("media of \(item)")
  }

  func mediaBytes(_ command: ReadMediaBytes) async throws(HostError) -> Data {
    throw .notFound("media of \(command.item)")
  }

  func cover(of item: EntityID) async throws(HostError) -> Data? { library?.cover(of: item) }
  func itemPDF(_ item: EntityID) async throws(HostError) -> Data { throw .notFound("content.pdf") }

  func itemImage(_ command: ReadItemImage) async throws(HostError) -> Data {
    guard library != nil, let data = SampleLibrary.picture("pingora") else { throw .notFound(command.name) }
    return data
  }

  func mediaSetup() async throws(HostError) -> MediaSetup {
    if let setup = library?.setup { return setup }
    return MediaSetup(
      components: await detectComponents(again: false), componentWork: [],
      speechModels: SpeechModel.allCases.map { SpeechModelStatus(model: $0, state: .absent) },
      speechModel: .recommended, browserLogin: .none)
  }

  func detectComponents(again: Bool) async -> [ComponentStatus] {
    Component.allCases.map { ComponentStatus(component: $0, installation: .missing) }
  }

  func installComponent(_ component: Component) async throws(HostError) -> Done { Done() }
  func downloadSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done { Done() }
  func deleteSpeechModel(_ model: SpeechModel) async throws(HostError) -> Done { Done() }
  func setSpeechModel(_ model: SpeechModel) async throws(HostError) -> MediaSetup { try await mediaSetup() }
  func setBrowserLogin(_ login: BrowserLogin) async throws(HostError) -> MediaSetup { try await mediaSetup() }
  func handOverBrowserCookies(_ cookies: [BrowserCookie]) async throws(HostError) -> Done { Done() }
}

/// Link previews, answered from the sample's pages without the network.
extension FakeHost {
  func linkPreview(of url: URL) async throws(HostError) -> LinkPreview {
    SampleLinks.preview(of: url)
  }

  func linkImage(of url: URL) async throws(HostError) -> Data? {
    SampleLinks.image(of: url)
  }
}
