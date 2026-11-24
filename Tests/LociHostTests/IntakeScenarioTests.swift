import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// O-S1, O-S2, I-S2: what a video goes through, by the choice it was taken in with.
struct IntakeScenarioTests {
  static func choice(
    _ keeping: ImportChoice.Keeping = .local, quality: ImportChoice.Quality = .hd720, subtitles: Bool = true,
    subtitleLanguage: String? = nil, recognition: ImportChoice.Recognizing? = .init(language: nil, model: .recommended),
    translation: ImportChoice.Translating? = .init(language: "zh-Hans", model: nil)
  ) -> ImportChoice {
    ImportChoice(
      keeping: keeping, quality: quality, siteSubtitles: subtitles, subtitleLanguage: subtitleLanguage,
      recognition: recognition, translation: translation)
  }

  /// O-S1: watched online with the site's subtitles, nothing but the subtitles is fetched.
  @Test func anOnlineVideoWithSubtitlesOnlyFetchesTheSubtitles() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: Self.choice(.online)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "--print").isEmpty)
      #expect(transcriber.heardFiles.isEmpty)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.origin == .platform)
      guard case .online = try await host.run(ReadPlayback(item: item.id)) else {
        Issue.record("expected it to play online")
        return
      }
    }
  }

  /// O-S1: watched online without subtitles, its sound is fetched to be recognized and deleted after.
  @Test func anOnlineVideoWithoutSubtitlesRecognizesATemporarySoundAndDeletesIt() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo"))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: Self.choice(.online)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "--print").count == 1)
      #expect(world.programs.calls(with: "-x").count == 1)
      #expect(transcriber.heardFiles.map(\.lastPathComponent) == ["media.m4a"])
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.segments.count == 3)
      #expect(try await host.run(ReadMediaPage(item: item.id)).downloaded == false)
      let folder = try #require(await host.localFile(.item(item.id))).url
      let left = try FileManager.default.subpathsOfDirectory(atPath: folder.path(percentEncoded: false))
      #expect(!left.contains { $0.hasSuffix(".m4a") })
    }
  }

  /// O-S2: kept on this Mac, the sound is recognized first and the video downloads once the transcript is out.
  @Test func aSavedVideoIsRecognizedBeforeItsVideoDownloads() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo"))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: Self.choice()))

      #expect(await job(host, item.id, where: isDone) != nil)
      let downloads = world.programs.calls(with: "--print")
      #expect(downloads.count == 2)
      #expect(downloads.first?.arguments.contains("-x") == true)
      #expect(downloads.last?.arguments.contains("--merge-output-format") == true)
      #expect(transcriber.heardFiles.map(\.lastPathComponent) == ["media.m4a"])
      #expect(try await host.run(ReadPlayback(item: item.id)) == .downloaded)
      #expect(try #require(await host.localFile(.media(item.id))).url.pathExtension == "mp4")
    }
  }

  /// O-S2, I-S2: the video downloads at the quality chosen.
  @Test(arguments: [(ImportChoice.Quality.hd1080, "1080"), (.hd720, "720")])
  func theChosenQualityIsDownloaded(quality: ImportChoice.Quality, height: String) async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: Self.choice(quality: quality)))

      #expect(await job(host, item.id, where: isDone) != nil)
      let video = try #require(world.programs.calls(with: "--merge-output-format").first)
      #expect(video.arguments.contains("bv*[height<=\(height)]+ba/b[height<=\(height)]/bv*+ba/b"))
    }
  }

  /// O-S2, I-S2: a video kept as sound only keeps the sound it was recognized from.
  @Test func anAudioOnlyVideoKeepsTheSoundItRecognized() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo"))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: Self.choice(quality: .audio)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "--print").count == 1)
      #expect(try #require(await host.localFile(.media(item.id))).url.pathExtension == "m4a")
    }
  }

  /// I-S2: with the site's subtitles turned off, speech is recognized even though the site has subtitles.
  @Test func turningSiteSubtitlesOffRecognizesInstead() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: Self.choice(subtitles: false)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "--write-subs").isEmpty)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.origin == .recognized(.recommended))
    }
  }

  /// I-S2: the site's subtitles are taken in the language chosen when the site has it.
  @Test func theChosenSubtitleLanguageIsTaken() async throws {
    try await withMediaHost { host, world in
      world.programs.site(
        Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles, subtitleLanguages: ["en", "ja"]))

      let item = try await host.run(
        AddLink(url: Links.url(Links.youtube), choice: Self.choice(.online, subtitleLanguage: "ja")))

      #expect(await job(host, item.id, where: isDone) != nil)
      let asked = try #require(world.programs.calls(with: "--write-subs").first)
      #expect(asked.arguments.contains("ja"))
    }
  }

  /// I-S2: recognition hears the language chosen, and the transcript is in it.
  @Test func recognitionHearsTheChosenLanguage() async throws {
    let transcriber = FakeTranscriber(Array(spoken.dropFirst()))
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel(.small)
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo"))
      let choice = Self.choice(.online, recognition: .init(language: "ja", model: .small), translation: nil)

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: choice))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(transcriber.heardLanguages == ["ja"])
      let transcript = try await host.run(ReadMediaPage(item: item.id)).transcript
      #expect(transcript?.language == "ja")
      #expect(transcript?.origin == .recognized(.small))
    }
  }

  /// I-S2: with translation turned off, the transcript is left as it is.
  @Test func noTranslationLeavesTheTranscriptUntranslated() async throws {
    try await withMediaHost { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))

      let item = try await host.run(
        AddLink(url: Links.url(Links.youtube), choice: Self.choice(.online, translation: nil)))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).translations.isEmpty)
      #expect(!world.agent.requests.contains { $0.hasPrefix("translate") })
    }
  }

  /// I-S2: translation goes into the language chosen, with the model chosen for it.
  @Test func translationRunsOnTheModelChosenForIt() async throws {
    try await withMediaHost { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
      let chosen = ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-reasoner")
      let choice = Self.choice(.online, translation: .init(language: "ja", model: chosen))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube), choice: choice))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.agent.requests.contains { $0.hasPrefix("translate ja ") })
      #expect(world.models.all.first == chosen)
      #expect(try await host.run(ReadMediaPage(item: item.id)).translations.map(\.language) == ["ja"])
    }
  }

  /// An item taken in before choices were kept downloads first, as it did.
  @Test func anOlderItemWithoutAChoiceKeepsItsStages() throws {
    let video = try Item(
      id: EntityID(), kind: .video(duration: nil), title: "Talk", source: Links.url(Links.youtube))

    #expect(Job.Stage.all(for: video, choice: nil) == [.resolve, .download, .transcribe, .translate, .outline])
    #expect(
      Job.Stage.all(for: video, choice: Self.choice())
        == [.resolve, .transcribe, .download, .translate, .outline])
    #expect(
      Job.Stage.all(for: video, choice: Self.choice(.online, translation: nil)) == [.resolve, .transcribe, .outline])
  }

  /// A job moves through its stages in the item's own order, and from a stage it no longer has to the next.
  @Test func theNextStageFollowsTheItemsOwnOrder() {
    let stages: [Job.Stage] = [.resolve, .transcribe, .download, .translate]

    #expect(JobRun.stage(in: stages, from: .transcribe, after: true) == .download)
    #expect(JobRun.stage(in: stages, from: .download, after: false) == .download)
    #expect(JobRun.stage(in: stages, from: .translate, after: true) == nil)
    #expect(JobRun.stage(in: stages, from: .extract, after: true) == .transcribe)
  }
}
