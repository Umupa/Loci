import LociModel
import Testing

@testable import LociUI

/// O-S7–O-S9.
@MainActor
struct StorageTests {
  func setup(using model: SpeechModel, ready: Set<SpeechModel>) -> MediaSetup {
    MediaSetup(
      components: [], componentWork: [],
      speechModels: SpeechModel.allCases.map {
        SpeechModelStatus(model: $0, state: ready.contains($0) ? .ready : .absent)
      },
      speechModel: model, browserLogin: .none)
  }

  /// O-S9.
  @Test func choosingAnotherModelAsksAboutTheOneItReplaces() {
    let setup = setup(using: .small, ready: [.small, .base])

    #expect(SpeechModels.replaced(by: .base, in: setup) == .small)
    #expect(SpeechModels.replaced(by: .small, in: setup) == nil)
  }

  @Test func aModelThatIsNotOnTheDiskIsNotAskedAbout() {
    #expect(SpeechModels.replaced(by: .base, in: setup(using: .small, ready: [.base])) == nil)
  }

  /// O-S7: the bar adds videos, podcasts and models apart.
  @Test func storageAddsVideosPodcastsAndModelsApart() {
    let report = StorageReport(
      capacity: 494_000_000_000, available: 100_000_000_000,
      items: [
        ItemSpace(item: EntityID(), isAudio: false, bytes: 400, fromLink: true),
        ItemSpace(item: EntityID(), isAudio: true, bytes: 90, fromLink: true),
        ItemSpace(item: EntityID(), isAudio: false, bytes: nil, fromLink: true),
      ], speechModels: [ModelSpace(model: .small, bytes: 500)])

    #expect(report.bytes(of: .video(duration: nil)) == 400)
    #expect(report.bytes(of: .audio(duration: nil)) == 90)
    #expect(report.modelBytes == 500)
  }
}
