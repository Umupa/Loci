import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// L-S3, L-S4, L-S5, L-S13: links to videos and episodes become items that play, then read.
struct MediaScenarioTests {
  /// L-S3: the card is there at once, plays online once resolved, and plays from the file once downloaded.
  @Test func aPastedVideoLinkPlaysOnlineWhileItDownloads() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", site: "jawed", duration: 19))
      await world.programs.downloads.close()
      let items = host.subscribe(AllItems())

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(item.title == "youtube.com/watch?v=jNQXAC9IVRw")
      #expect(item.kind == .video(duration: nil))
      #expect(await value(items) { $0.map(\.id) == [item.id] } != nil)
      #expect(await job(host, item.id, where: isRunning(.download)) != nil)
      let playing = try await host.run(ReadPlayback(item: item.id))
      guard case .online(let stream) = playing else {
        Issue.record("expected an online stream, got \(playing)")
        return
      }
      #expect(stream.url.host() == "media.example.com")
      #expect(!stream.audioOnly)
      let titled = await value(items) { $0.first?.title == "Me at the zoo" }
      #expect(titled?.first?.site == "jawed")
      #expect(titled?.first?.kind == .video(duration: .seconds(19)))
      #expect(try await host.run(ReadCover(item: item.id)) == Data("jpeg".utf8))

      await world.programs.downloads.open()

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadPlayback(item: item.id)) == .downloaded)
      let file = try #require(await host.localFile(.media(item.id))).url
      #expect(file.lastPathComponent == "media.mp4")
      #expect(world.programs.calls(with: "--merge-output-format").count == 1)
      #expect(world.programs.calls(with: "-J").count == 1)
      #expect(world.programs.calls(with: "--print").first?.arguments.contains("--load-info-json") == true)
    }
  }

  /// L-S4: an episode is something to listen to, has its cover, and downloads only its sound.
  @Test func aPodcastEpisodeBecomesAudioWithACover() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(
        Links.episode, FakeSite(title: "Finally, a Vaccine for Cancer", site: "The Daily", audio: true))

      let item = try await host.run(AddLink(url: Links.url(Links.episode)))

      #expect(item.kind == .audio(duration: nil))
      #expect(await job(host, item.id, where: isDone) != nil)
      let saved = try #require(try await host.run(ListItems()).first)
      #expect(saved.kind == .audio(duration: .seconds(120)))
      #expect(saved.site == "The Daily")
      #expect(try await host.run(ReadCover(item: item.id)) != nil)
      let download = try #require(world.programs.calls(with: "--print").first)
      #expect(download.arguments.contains("-x"))
      #expect(try await host.run(ReadPlayback(item: item.id)) == .downloaded)
      let file = try #require(await host.localFile(.media(item.id))).url
      #expect(file.lastPathComponent == "media.m4a")
    }
  }

  /// L-S5: the site's own subtitles are the transcript, and nothing is recognized.
  @Test func subtitlesFromTheSiteBecomeTheTranscriptWithoutRecognition() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      world.programs.site(
        Links.youtube,
        FakeSite(title: "Me at the zoo", subtitles: zooSubtitles, chapters: [(0, "Intro"), (5, "Trunks")]))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(await job(host, item.id, where: isDone) != nil)
      let page = try await host.run(ReadMediaPage(item: item.id))
      #expect(page.transcript?.origin == .platform)
      #expect(page.transcript?.segments.count == 2)
      #expect(page.outline?.chapters.map(\.title) == ["Intro", "Trunks"])
      #expect(page.outline?.highlights.map(\.title) == ["Start"])
      #expect(page.translations.map(\.language) == ["zh-Hans"])
      #expect(page.downloaded)
      #expect(transcriber.startedFrom.isEmpty)
    }
  }

  /// L-S5: without subtitles, speech is recognized and the sentences show up while it runs.
  @Test func withoutSubtitlesSentencesAppearAsTheyAreRecognized() async throws {
    let transcriber = FakeTranscriber(spoken, pauseAfter: 6)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))
      let media = host.subscribe(ItemMedia(item: item.id))

      let growing = await value(media) { $0.transcript?.segments.count == 2 }
      #expect(growing?.transcript?.segments.map(\.text) == ["The scheduler filters nodes.", "Then it scores them."])
      #expect(growing?.transcript?.origin == .recognized(.recommended))
      let recognizing = await job(host, item.id) { job in
        guard case .running(let share) = job?.state, job?.stage == .transcribe else { return false }
        return share == Fraction(0.8)
      }
      #expect(recognizing != nil)
    }
  }

  /// L-S13: what a card shows comes from the item list and the cover.
  @Test func aCardHasItsTitleSiteDurationAndCover() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", site: "jawed", duration: 19))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(await job(host, item.id, where: isDone) != nil)
      let card = try #require(try await host.run(ListItems()).first)
      #expect(card.title == "Me at the zoo")
      #expect(card.site == "jawed")
      #expect(card.kind == .video(duration: .seconds(19)))
      #expect(card.published == Timestamp(millisecondsSince1970: 1_794_825_900_000))
      #expect(try await host.run(ReadCover(item: item.id)) == Data("jpeg".utf8))
    }
  }

  /// L-S13: a card that shows the fetched title already has its cover; the window reads a cover once per
  /// version of the item, so a cover arriving later would not show until the app restarts.
  @Test func theFetchedTitleArrivesWithTheCover() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", site: "jawed", duration: 19))
      await world.network.images.close()
      let items = host.subscribe(AllItems())

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
      Task {
        try? await Task.sleep(for: .milliseconds(300))
        await world.network.images.open()
      }

      #expect(await value(items) { $0.first?.title == "Me at the zoo" } != nil)
      #expect(try await host.run(ReadCover(item: item.id)) == Data("jpeg".utf8))
    }
  }

  /// A video or audio file on this Mac is copied or linked, and its speech recognized.
  @Test(arguments: [ImportMode.copy, .link])
  func anImportedFilePlaysFromWhereItIsAndIsRecognized(mode: ImportMode) async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      let file = world.place.root.appending(path: ".outside/scheduling talk.wav")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Silence.wav(seconds: 1).write(to: file)

      let item = try await host.run(ImportMediaFile(upload: try await host.upload(LocalFile(file)), mode: mode))

      #expect(item.title == "scheduling talk")
      #expect(item.kind == .audio(duration: .seconds(1)))
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.segments.count == 3)
      #expect(try await host.run(ReadPlayback(item: item.id)) == .downloaded)
      let media = try #require(await host.localFile(.media(item.id))).url
      #expect(media.lastPathComponent == "media.wav")
      let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: media.path)) != nil
      #expect(isLink == (mode == .link))
    }
  }

  @Test func aFileWithoutSoundIsRefused() async throws {
    try await withMediaHost { host, world in
      let file = world.place.root.appending(path: ".outside/notes.txt")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("text".utf8).write(to: file)

      await #expect(throws: HostError.self) {
        try await host.run(ImportMediaFile(upload: try await host.upload(LocalFile(file)), mode: .copy))
      }
      #expect(try await host.run(ListItems()).isEmpty)
    }
  }
}

/// One-channel 16-bit PCM silence, which AVFoundation reads.
enum Silence {
  static func wav(seconds: Int) -> Data {
    let rate: UInt32 = 16_000
    let samples = Data(count: Int(rate) * seconds * 2)
    var data = Data("RIFF".utf8)
    func append<Value: FixedWidthInteger>(_ value: Value) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    append(UInt32(36 + samples.count))
    data.append(Data("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(rate)
    append(rate * 2)
    append(UInt16(2))
    append(UInt16(16))
    data.append(Data("data".utf8))
    append(UInt32(samples.count))
    data.append(samples)
    return data
  }
}
