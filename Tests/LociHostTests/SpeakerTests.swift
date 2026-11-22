import Foundation
import LociHost
import LociMedia
import LociModel
import Synchronization
import Testing

struct SpeakerTests {
  @Test func anEpisodeShowsSeparationProgressAndKeepsNamesAcrossTheWholeTranscript() async throws {
    let diarizer = FakeDiarizer()
    await diarizer.waiting.close()
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    try world.installModel()
    let transcriber = FakeTranscriber(spoken)
    let host = try await world.start(transcriber: transcriber, diarizer: diarizer, provider: .codex)
    world.programs.site(Links.episode, FakeSite(title: "Scheduling", description: "Maya hosts.", audio: true))
    world.agent.setSpeakerNames([1: "Maya"])
    let item = try await host.run(
      AddLink(url: Links.url(Links.episode), choice: Self.choice(recognize: true)))
    let media = host.subscribe(ItemMedia(item: item.id))
    let progress = await job(host, item.id) {
      $0?.stage == .diarize && $0?.state == .running(progress: Fraction(0.42))
    }
    await diarizer.waiting.open()

    #expect(progress != nil)
    let labeled = await value(media) { $0.transcript?.speakers.count == 2 }
    #expect(labeled?.transcript?.segments.map(\.speaker) == [1, 2, 1])
    #expect(labeled?.transcript?.speakers.map(\.name) == ["Maya", nil])
    #expect(world.agent.speakerDescriptions == ["Maya hosts."])
    #expect(diarizer.files == transcriber.heardFiles)
    let done = await job(host, item.id, where: isDone)
    #expect(done != nil)
    #expect(diarizer.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

    let changes = host.subscribe(ItemMedia(item: item.id))
    _ = try await host.run(RenameSpeaker(item: item.id, speaker: 1, name: "  Maya Chen  "))
    let renamed = await value(changes) { $0.transcript?.name(ofSpeaker: 1) == "Maya Chen" }
    #expect(renamed?.transcript?.segments.map(\.speaker) == [1, 2, 1])
    await #expect(throws: HostError.self) {
      try await host.run(RenameSpeaker(item: item.id, speaker: 3, name: "Nobody"))
    }
    await #expect(throws: HostError.self) {
      try await host.run(RenameSpeaker(item: item.id, speaker: 1, name: "  "))
    }
    await host.close()

    let reopened = try await world.start(provider: .codex)
    let persisted = try await reopened.run(ReadMediaPage(item: item.id)).transcript
    #expect(persisted?.speakers.map(\.name) == ["Maya Chen", nil])
    await reopened.close()
  }

  @Test func platformSubtitlesAreLabeledWithoutRunningRecognition() async throws {
    let diarizer = FakeDiarizer()
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    let transcriber = FakeTranscriber([])
    let host = try await world.start(transcriber: transcriber, diarizer: diarizer, provider: .codex)
    world.programs.site(Links.episode, FakeSite(title: "Scheduling", audio: true, subtitles: zooSubtitles))
    let item = try await host.run(
      AddLink(url: Links.url(Links.episode), choice: Self.choice(recognize: false)))

    #expect(await job(host, item.id, where: isDone) != nil)
    let transcript = try await host.run(ReadMediaPage(item: item.id)).transcript
    #expect(transcript?.origin == .platform)
    #expect(transcript?.segments.map(\.speaker) == [1, 2])
    #expect(transcriber.heardFiles.isEmpty)
    #expect(diarizer.files.count == 1)
    await host.close()
  }

  @Test func aSeparationFailureLeavesTheTranscriptAndFinishesTheJob() async throws {
    let diarizer = FakeDiarizer(fails: true)
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    try world.installModel()
    let host = try await world.start(transcriber: FakeTranscriber(spoken), diarizer: diarizer, provider: .codex)
    world.programs.site(Links.episode, FakeSite(title: "Scheduling", audio: true))
    let item = try await host.run(
      AddLink(url: Links.url(Links.episode), choice: Self.choice(recognize: true)))

    #expect(await job(host, item.id, where: isDone) != nil)
    let media = try await host.run(ReadMediaPage(item: item.id))
    #expect(media.transcript?.segments.count == 3)
    #expect(media.transcript?.speakers.isEmpty == true)
    #expect(media.outline != nil)
    #expect(diarizer.files.count == 1)
    #expect(diarizer.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    await host.close()
  }

  @Test func aVideoNeverRunsSpeakerSeparation() async throws {
    let diarizer = FakeDiarizer()
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    try world.installModel()
    let host = try await world.start(transcriber: FakeTranscriber(spoken), diarizer: diarizer, provider: .codex)
    world.programs.site(Links.youtube, FakeSite(title: "Scheduling"))
    let item = try await host.run(
      AddLink(url: Links.url(Links.youtube), choice: Self.choice(recognize: true)))

    #expect(await job(host, item.id, where: isDone) != nil)
    #expect(diarizer.files.isEmpty)
    #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.speakers.isEmpty == true)
    await host.close()
  }

  private static func choice(recognize: Bool) -> ImportChoice {
    ImportChoice(
      keeping: .online, quality: .audio, siteSubtitles: true,
      recognition: recognize ? .init(language: nil, model: .recommended) : nil, translation: nil)
  }
}

private final class FakeDiarizer: Diarizing {
  private let heard = Mutex<[URL]>([])
  private let fails: Bool
  let waiting = Latch(open: true)

  init(fails: Bool = false) {
    self.fails = fails
  }

  var files: [URL] { heard.withLock { $0 } }

  func speakers(in audio: URL, models: URL, progress: @escaping @Sendable (Fraction) -> Void) async throws
    -> [SpeakerTurn]
  {
    heard.withLock { $0.append(audio) }
    progress(Fraction(0.42))
    await waiting.wait()
    if fails { throw CocoaError(.fileReadCorruptFile) }
    return [
      try SpeakerTurn(speaker: "A", start: .zero, end: .seconds(1.5)),
      try SpeakerTurn(speaker: "B", start: .seconds(2), end: .seconds(3)),
      try SpeakerTurn(speaker: "A", start: .seconds(4), end: .seconds(8)),
    ]
  }
}
