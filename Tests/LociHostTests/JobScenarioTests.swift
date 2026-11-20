import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// L-S9, L-S10, L-S11, L-S16: jobs that wait, carry on after quitting, fail with a way out, or stop.
struct JobScenarioTests {
  /// L-S9: a missing component is asked for on the item itself, and the job carries on once it is there.
  @Test func aMissingComponentMakesTheJobWaitUntilItIsInstalled() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken), components: []) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(await job(host, item.id, where: state(.waiting(.component(.ytDlp)))) != nil)
      _ = try await host.run(InstallComponent(.ytDlp))
      #expect(await job(host, item.id, where: state(.waiting(.component(.ffmpeg)))) != nil)
      _ = try await host.run(InstallComponent(.ffmpeg))
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.network.requests.map(\.lastPathComponent).contains("yt-dlp_macos.zip"))
    }
  }

  /// L-S9: recognition waits for its model on the item, and starts once the model is downloaded.
  @Test func aMissingSpeechModelMakesRecognitionWaitUntilItIsDownloaded() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      #expect(await job(host, item.id, where: state(.waiting(.speechModel(.recommended)))) != nil)
      _ = try await host.run(DownloadSpeechModel(.recommended))
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.segments.count == 3)
    }
  }

  /// Recognition runs one item at a time; the second waits its turn.
  @Test func onlyOneRecognitionRunsAtATime() async throws {
    let transcriber = FakeTranscriber(spoken)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      await transcriber.gate.close()
      world.programs.site(Links.bilibili, FakeSite(title: "One"))
      world.programs.site(Links.youtube, FakeSite(title: "Two"))

      let one = try await host.run(AddLink(url: Links.url(Links.bilibili)))
      let two = try await host.run(AddLink(url: Links.url(Links.youtube)))
      let jobs = host.subscribe(AllJobs())
      let turns = await value(jobs) { jobs in
        jobs.count == 2 && jobs.allSatisfy { $0.stage == .transcribe }
          && jobs.contains { $0.state == .queued } && jobs.contains { $0.state == .running(progress: nil) }
      }
      #expect(turns != nil)
      try await Task.sleep(for: .milliseconds(100))
      await transcriber.gate.open()

      #expect(await job(host, one.id, where: isDone) != nil)
      #expect(await job(host, two.id, where: isDone) != nil)
      #expect(transcriber.mostAtOnce == 1)
    }
  }

  /// L-S10: recognition stopped by quitting carries on after the last sentence written.
  @Test func recognitionCarriesOnAfterQuittingFromTheLastSentence() async throws {
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    try world.installModel()
    world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))
    let first = try await world.start(transcriber: FakeTranscriber(spoken, pauseAfter: 6))
    let item = try await first.run(AddLink(url: Links.url(Links.bilibili)))
    let media = first.subscribe(ItemMedia(item: item.id))
    #expect(await value(media) { $0.transcript?.segments.count == 2 } != nil)
    await first.close()

    let again = FakeTranscriber(spoken)
    let second = try await world.start(transcriber: again)

    #expect(await job(second, item.id, where: isDone) != nil)
    #expect(again.startedFrom == [.milliseconds(2950)])
    let texts = try await second.run(ReadMediaPage(item: item.id)).transcript?.segments.map(\.text)
    #expect(texts == ["The scheduler filters nodes.", "Then it scores them.", "Finally it binds the pod."])
    #expect(world.programs.calls(with: "-x").count == 1)
    #expect(world.programs.calls(with: "--merge-output-format").count == 1)
    await second.close()
  }

  /// L-S10: a download stopped by quitting starts again on the next launch and picks up its part.
  @Test func aDownloadCarriesOnAfterQuitting() async throws {
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    try world.installModel()
    world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
    await world.programs.downloads.close()
    let first = try await world.start()
    let item = try await first.run(AddLink(url: Links.url(Links.youtube)))
    #expect(await job(first, item.id, where: isRunning(.download)) != nil)
    await first.close()
    await world.programs.downloads.open()

    let second = try await world.start()

    #expect(await job(second, item.id, where: isDone) != nil)
    let downloads = world.programs.calls(with: "--print")
    #expect(downloads.count == 2)
    #expect(downloads.allSatisfy { $0.arguments.contains("--continue") })
    await second.close()
  }

  /// I-S9: a paused download stays paused across a quit with how far it had got, and resuming picks up the part
  /// already downloaded.
  @Test func aPausedDownloadStaysPausedAfterQuittingAndResumesFromItsPart() async throws {
    let world = MediaWorld()
    defer { world.place.remove() }
    try world.install()
    try world.installModel()
    world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
    await world.programs.downloads.close()
    let first = try await world.start()
    let item = try await first.run(AddLink(url: Links.url(Links.youtube)))
    let downloading = await job(first, item.id) { job in
      if case .running(_?, _) = job?.state, job?.stage == .download { true } else { false }
    }
    #expect(downloading != nil)
    _ = try await first.run(PauseJob(item: item.id))
    await first.close()
    await world.programs.downloads.open()

    let second = try await world.start()

    let paused = await job(second, item.id, where: isPaused) ?? nil
    #expect(paused?.stage == .download)
    guard case .paused(let progress?) = paused?.state else {
      Issue.record("expected the share the download had got to, got \(String(describing: paused))")
      return
    }
    #expect(progress.value > 0)
    try await Task.sleep(for: .milliseconds(100))
    #expect(world.programs.calls(with: "--print").count == 1)
    _ = try await second.run(RetryJob(item: item.id))
    #expect(await job(second, item.id, where: isDone) != nil)
    let downloads = world.programs.calls(with: "--print")
    #expect(downloads.count == 2)
    #expect(downloads.allSatisfy { $0.arguments.contains("--continue") })
    await second.close()
  }

  /// A job tells which stages its item goes through, so the reader sees what is left.
  @Test func aJobCarriesTheStagesItsItemGoesThrough() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      let waiting = await job(host, item.id, where: state(.waiting(.speechModel(.recommended)))) ?? nil
      #expect(waiting?.stages == [.resolve, .transcribe, .download, .translate, .outline])
    }
  }

  /// L-S11 and L-S16: a site that wants a signed-in visitor waits, and carries on once cookies arrive.
  @Test func aVideoThatNeedsASignInWaitsForOneAndThenCarriesOn() async throws {
    try await withMediaHost { host, world in
      try world.installModel()
      world.programs.site(
        Links.bilibili,
        FakeSite(title: "Members", refusal: "ERROR: [BiliBili] x: This video is only for members; login required"))

      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))

      #expect(await job(host, item.id, where: state(.waiting(.login(site: "www.bilibili.com")))) != nil)
      world.programs.site(Links.bilibili, FakeSite(title: "Members", subtitles: zooSubtitles))
      _ = try await host.run(
        HandOverBrowserCookies([
          BrowserCookie(domain: ".bilibili.com", path: "/", name: "SESSDATA", value: "x", secure: true, expires: nil)
        ]))
      #expect(await job(host, item.id, where: isDone) != nil)
      let last = try #require(world.programs.calls(with: "-J").last)
      #expect(last.arguments.contains("--cookies"))
    }
  }

  /// L-S16: the browser chosen in the settings lends its sign-in to every fetch.
  @Test func theChosenBrowsersSignInGoesWithEveryFetch() async throws {
    try await withMediaHost { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))

      let setup = try await host.run(SetBrowserLogin(.chrome))
      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      #expect(setup.browserLogin == .chrome)
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "-J").allSatisfy { $0.arguments.contains("--cookies-from-browser") })
    }
  }

  /// L-S11: each failure says why and offers what helps.
  @Test(arguments: [
    (
      "ERROR: [youtube] x: Unable to extract nsig function; please report this issue",
      Job.Remedy.updateComponent(.ytDlp), Job.Cause?.some(.outdated)
    ),
    ("ERROR: unable to download webpage: timed out", .retry, .network),
    ("ERROR: [youtube] x: This video is unavailable", .openSource, .unavailable),
    ("ERROR: Postprocessing: Conversion failed!", .retry, nil),
  ])
  func aFailedFetchSaysWhyAndWhatHelps(said: String, remedy: Job.Remedy, cause: Job.Cause?) async throws {
    try await withMediaHost { host, world in
      world.programs.site(Links.youtube, FakeSite(title: "x", refusal: said))

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))

      let failed = await job(host, item.id) { job in
        if case .failed = job?.state { true } else { false }
      }
      guard case .failed(let failure) = failed??.state else {
        Issue.record("expected a failure")
        return
      }
      #expect(failure.remedy == remedy)
      #expect(failure.cause == cause)
      #expect(!failure.reason.hasPrefix("ERROR"))
    }
  }

  /// L-S11: retrying after the cause is gone carries on from where it failed.
  @Test func retryingAFailedJobCarriesOn() async throws {
    try await withMediaHost { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
      world.programs.refuseDownloads("ERROR: unable to download video data: HTTP Error 403")

      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
      let failed = await job(host, item.id) { job in
        if case .failed = job?.state, job?.stage == .download { true } else { false }
      }
      #expect(failed != nil)
      world.programs.refuseDownloads(nil)
      let retried = try await host.run(RetryJob(item: item.id))

      #expect(retried.stage == .download)
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(world.programs.calls(with: "-J").count == 1)
    }
  }

  /// I-S9: pausing keeps what was made; resuming carries on from there.
  @Test func aPausedJobKeepsItsWorkAndResumingCarriesOn() async throws {
    let transcriber = FakeTranscriber(spoken, pauseAfter: 6)
    try await withMediaHost(transcriber: transcriber) { host, world in
      try world.installModel()
      world.programs.site(Links.bilibili, FakeSite(title: "Scheduling"))
      let item = try await host.run(AddLink(url: Links.url(Links.bilibili)))
      let media = host.subscribe(ItemMedia(item: item.id))
      #expect(await value(media) { $0.transcript?.segments.count == 2 } != nil)

      _ = try await host.run(PauseJob(item: item.id))

      #expect(await job(host, item.id, where: isPaused) != nil)
      #expect(try await host.run(ReadMediaPage(item: item.id)).transcript?.segments.count == 2)
      #expect(try await host.run(RetryJob(item: item.id)).stage == .transcribe)
      #expect(await job(host, item.id, where: isDone) != nil)
      #expect(transcriber.startedFrom.last == .milliseconds(2950))
    }
  }

  /// An item whose job is gone starts again where its files say, such as after the database was replaced.
  @Test func retryingAnItemWithoutAJobStartsWhereItsFilesStop() async throws {
    try await withMediaHost(transcriber: FakeTranscriber(spoken)) { host, world in
      try world.installModel()
      world.programs.site(Links.youtube, FakeSite(title: "Me at the zoo", subtitles: zooSubtitles))
      let item = try await host.run(AddLink(url: Links.url(Links.youtube)))
      #expect(await job(host, item.id, where: isDone) != nil)

      await #expect(throws: HostError.self) { try await host.run(RetryJob(item: item.id)) }
    }
  }
}

/// Whether the job is paused, however far it had got.
@Sendable func isPaused(_ job: Job?) -> Bool {
  if case .paused = job?.state { return true }
  return false
}
