import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// I-S1, I-S3–I-S6: what the import panel reads before a link is taken in, and the choice it is taken in with.
struct ImportScenarioTests {
  /// I-S1: the panel fills with the real title, channel, duration, cover, sizes and subtitle languages.
  @Test func probingAVideoLinkReadsTitleChannelDurationCoverAndSizes() async throws {
    try await withMediaHost { host, world in
      world.programs.site(
        Links.youtube,
        FakeSite(
          title: "Me at the zoo", site: "jawed", duration: 19, subtitles: zooSubtitles,
          subtitleLanguages: ["en", "ja"], sized: true))

      let preview = try await host.run(ProbeLink(url: Links.url(Links.youtube)))

      guard case .media(let media) = preview else {
        Issue.record("expected media, got \(preview)")
        return
      }
      #expect(media.title == "Me at the zoo")
      #expect(media.site == "jawed")
      #expect(media.duration == .seconds(19))
      #expect(media.cover == FakeNetwork.cover)
      #expect(!media.isAudio)
      #expect(media.sizes == [.hd1080: 415_000_000, .hd720: 195_000_000, .audio: 15_000_000])
      #expect(media.subtitles == ["en", "ja"])
      #expect(media.spokenSubtitles == "en")
    }
  }

  /// I-S5: a link already in the library gives that item, without asking the site.
  @Test func probingALinkAlreadyInTheLibraryGivesThatItem() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo"))
      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
      #expect(await job(host, item.id, where: isDone) != nil)
      let asked = world.programs.calls(with: "-J").count

      let preview = try await host.run(ProbeLink(url: Links.url(Links.youtube)))

      guard case .saved(let saved) = preview else {
        Issue.record("expected the saved item, got \(preview)")
        return
      }
      #expect(saved.id == item.id)
      #expect(world.programs.calls(with: "-J").count == asked)
    }
  }

  /// I-S1, A-S5: taking in a probed link starts with its real title and cover, and the page is read once.
  @Test func addingAProbedLinkDoesNotReadThePageAgain() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", site: "jawed", duration: 19))
      _ = try await host.run(ProbeLink(url: Links.url(Links.youtube)))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(item.title == "Me at the zoo")
      #expect(item.kind == .video(duration: .seconds(19)))
      #expect(try await host.run(ReadCover(item: item.id)) == FakeNetwork.cover)
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "-J").count == 1)
      #expect(world.programs.calls(with: "--print").allSatisfy { $0.arguments.contains("--load-info-json") })
    }
  }

  /// I-S3: before any choice, a video is kept at 720p with the site's subtitles and translated by Loci's runtime.
  @Test func theFirstImportChoiceIsTheDefault() async throws {
    try await withMediaHost(readerLanguage: "zh-Hans") { host, _ in
      let choice = try await host.run(ReadImportChoice())

      #expect(choice == .first(readerLanguage: "zh-Hans", speechModel: .recommended))
      #expect(choice.keeping == .local)
      #expect(choice.quality == .hd720)
      #expect(choice.siteSubtitles)
      #expect(choice.translation == ImportChoice.Translating(language: "zh-Hans", runtime: nil))
    }
  }

  /// I-S3: the choice something was taken in with is where the next panel starts.
  @Test func addingWithAChoiceMakesItTheNextDefault() async throws {
    try await withMediaHost { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
      let choice = ImportChoice(
        keeping: .online, quality: .hd1080, siteSubtitles: true, recognition: nil,
        translation: .init(language: "ja", runtime: Runtime(provider: .codex)))

      _ = try await host.run(AddLink(url: Links.url(Links.youtube), choice: choice))

      #expect(try await host.run(ReadImportChoice()) == choice)
    }
  }

  /// I-S6: `loci save` takes the last choice, and leaves it as it was.
  @Test func aLinkSavedWithoutAChoiceUsesTheLastOne() async throws {
    try await withMediaHost { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "One", subtitles: zooSubtitles))
      world.programs.site(Links.bilibili, FakeSite(title: "Two", subtitles: zooSubtitles))
      let online = ImportChoice(
        keeping: .online, quality: .hd720, siteSubtitles: true, recognition: nil, translation: nil)
      let first = try await host.run(AddLink(url: Links.url(Links.youtube), choice: online))
      #expect(await job(host, first.id, where: isDone) != nil)

      let second = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      #expect(await job(host, second.id, where: isDone) != nil)
      #expect(try await host.run(ReadPlayback(item: second.id)) != .downloaded)
      #expect(world.programs.calls(with: "--print").isEmpty)
      #expect(try await host.run(ReadImportChoice()) == online)
    }
  }

  /// I-S4: the sentence written in the panel stays with the item while its job rewrites it.
  @Test func theReasonGivenWhenAddingStaysWithTheItemThroughItsJob() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", site: "jawed", duration: 19))

      let item = try await host.run(
        AddLink(url: Links.url(Links.youtube), why: "  The first video, to see how it began.  "))

      #expect(item.why == "The first video, to see how it began.")
      #expect(await job(host, item.id, where: isDone) != nil)
      let page = try await host.itemPage(item.id)
      #expect(page.item.title == "Me at the zoo")
      #expect(page.item.language == "en")
      #expect(page.item.why == "The first video, to see how it began.")
    }
  }

  /// I-S6: a media file taken in with recognition turned off has no transcript, and keeps its reason.
  @Test func aMediaFileTakenInWithoutRecognitionHasNoTranscript() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      let file = world.place.root.appending(path: ".outside/talk.wav")
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Silence.wav(seconds: 1).write(to: file)
      let choice = ImportChoice(
        keeping: .local, quality: .hd720, siteSubtitles: false, recognition: nil, translation: nil)

      let item = try await host.run(
        ImportMediaFile(upload: try await host.upload(LocalFile(file)), mode: .copy, choice: choice, why: "A talk"))

      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript == nil)
      #expect(transcriber.heardFiles.isEmpty)
      #expect(try await host.itemPage(item.id).item.why == "A talk")
    }
  }
}
