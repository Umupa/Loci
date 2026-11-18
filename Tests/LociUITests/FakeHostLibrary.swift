import Foundation
import LociModel

/// The library's commands, answered with nothing in progress and nothing installed.
extension FakeHost {
  func addLink(_ command: AddLink) async throws(HostError) -> Item { sample.items[0] }
  func importMediaFile(_ command: ImportMediaFile) async throws(HostError) -> Item { sample.items[0] }

  func retryJob(_ item: EntityID) async throws(HostError) -> Job {
    Job(item: item, stage: .resolve, state: .queued)
  }

  func cancelJob(_ item: EntityID) async throws(HostError) -> Done { Done() }
  func jobs() async throws(HostError) -> [Job] { [] }
  func job(of item: EntityID) async throws(HostError) -> Job? { nil }

  func mediaPage(_ item: EntityID) async throws(HostError) -> MediaPage {
    MediaPage(transcript: nil, translations: [], outline: nil, hasCover: false, downloaded: false)
  }

  func playback(_ command: ReadPlayback) async throws(HostError) -> Playback {
    throw .notFound("media of \(command.item)")
  }

  func cover(of item: EntityID) async throws(HostError) -> Data? { nil }
  func itemPDF(_ item: EntityID) async throws(HostError) -> Data { throw .notFound("content.pdf") }
  func itemImage(_ command: ReadItemImage) async throws(HostError) -> Data { throw .notFound(command.name) }

  func mediaSetup() async throws(HostError) -> MediaSetup {
    MediaSetup(
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
