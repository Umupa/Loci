import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// O-S6–O-S8: what the media takes, freeing it and keeping it again.
struct StorageScenarioTests {
  /// A downloaded video, its transcript and outline, and a note on it.
  private func downloaded(_ host: LocalHost, _ world: MediaWorld) async throws -> Item {
    try world.installModel()
    world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
    let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
    #expect(await job(host, item.id, where: isDone) != nil)
    _ = try await host.run(
      AddNote(locator: .item(item.id, .time(try TimeSpan(start: .seconds(1), end: .seconds(4)))), excerpt: "elephants"))
    return item
  }

  @Test func storageCountsEachItemsMediaAndEachDownloadedModel() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      let item = try await downloaded(host, world)

      let report = try await host.storage()

      #expect(report.items.map(\.item) == [item.id])
      #expect((report.items.first?.bytes ?? 0) > 0)
      #expect(report.items.first?.fromLink == true)
      #expect(report.speechModels.map(\.model) == [.recommended])
      #expect(report.capacity != nil)
    }
  }

  @Test func freeingSpaceDeletesTheMediaAndKeepsTranscriptTranslationsNotesAndOutline() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      let item = try await downloaded(host, world)
      let before = try await host.run(ReadMediaPage(item: item.id))

      _ = try await host.run(FreeMediaSpace(item: item.id))

      let after = try await host.run(ReadMediaPage(item: item.id))
      #expect(!after.downloaded)
      #expect(after.transcript == before.transcript)
      #expect(after.translations == before.translations)
      #expect(after.outline == before.outline)
      #expect(try await host.notes(on: .item(item.id)).count == 1)
      #expect(try await host.storage().items.first?.bytes == nil)
      guard case .online = try await host.run(ReadPlayback(item: item.id)) else {
        Issue.record("expected to play online")
        return
      }
    }
  }

  @Test func anItemWhoseSpaceWasFreedIsNotDownloadedAgainWhenRetried() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      let item = try await downloaded(host, world)
      _ = try await host.run(FreeMediaSpace(item: item.id))

      await #expect(throws: HostError.self) { try await host.run(RetryJob(item: item.id)) }
      #expect(world.programs.calls(with: "--print").count == 1)
    }
  }

  @Test func savingLocallyDownloadsTheMediaAgain() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      let item = try await downloaded(host, world)
      _ = try await host.run(FreeMediaSpace(item: item.id))

      _ = try await host.run(SaveMediaLocally(item: item.id))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).downloaded)
      #expect(world.programs.calls(with: "--print").count == 2)
    }
  }
}
