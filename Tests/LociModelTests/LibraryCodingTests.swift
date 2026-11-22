import Foundation
import Testing

@testable import LociModel

/// The library's commands, replies and feeds survive the trip a remote host will give them.
struct LibraryCodingTests {
  static func roundTrips<Value: Codable>(_ value: Value) throws -> Bool {
    try HostCodingTests.roundTrips(value)
  }

  @Test func everyLibraryCommandSurvivesJSON() throws {
    #expect(try Self.roundTrips(AddLink(url: URL(string: "https://youtu.be/x")!)))
    #expect(try Self.roundTrips(ImportMediaFile(upload: Upload(id: Fixture.item), mode: .link)))
    #expect(try Self.roundTrips(RetryJob(item: Fixture.item)))
    #expect(try Self.roundTrips(PauseJob(item: Fixture.item)))
    #expect(try Self.roundTrips(ListJobs()))
    #expect(try Self.roundTrips(ReadPlayback(item: Fixture.item, refresh: true)))
    #expect(try Self.roundTrips(ReadCover(item: Fixture.item)))
    #expect(try Self.roundTrips(ReadItemPDF(item: Fixture.item)))
    #expect(try Self.roundTrips(ReadItemImage(item: Fixture.item, name: "images/a.png")))
    #expect(try Self.roundTrips(ReadMediaPage(item: Fixture.item)))
    #expect(try Self.roundTrips(RenameSpeaker(item: Fixture.item, speaker: 1, name: "Maya")))
    #expect(try Self.roundTrips(ReadLinkPreview(url: URL(string: "https://github.com/e2b-dev/infra")!)))
    #expect(try Self.roundTrips(ReadLinkImage(url: URL(string: "https://github.com/e2b-dev/infra")!)))
    #expect(try Self.roundTrips(ReadWebPicture(url: URL(string: "https://example.com/cover.jpg")!)))
    #expect(
      try Self.roundTrips(
        LinkPreview(
          url: URL(string: "https://github.com/e2b-dev/infra")!, title: "e2b-dev/infra", site: "GitHub",
          summary: nil, image: URL(string: "https://opengraph.githubassets.com/1/e2b-dev/infra"))))
    #expect(try Self.roundTrips(ReadMediaSetup()))
    #expect(try Self.roundTrips(ReadMediaFileInfo(item: Fixture.item)))
    #expect(try Self.roundTrips(ReadMediaBytes(item: Fixture.item, offset: 1 << 33, length: 65_536)))
    #expect(try Self.roundTrips(DetectComponents(again: true)))
    #expect(try Self.roundTrips(InstallComponent(.quickJS)))
    #expect(try Self.roundTrips(DownloadSpeechModel(.base)))
    #expect(try Self.roundTrips(DeleteSpeechModel(.base)))
    #expect(try Self.roundTrips(SetSpeechModel(.largeV3)))
    #expect(try Self.roundTrips(SetBrowserLogin(.firefox)))
    #expect(
      try Self.roundTrips(
        HandOverBrowserCookies([
          BrowserCookie(
            domain: ".bilibili.com", path: "/", name: "SESSDATA", value: "x", secure: true,
            expires: Timestamp(millisecondsSince1970: 1_800_000_000_000))
        ])))
  }

  @Test func everyLibraryReplyAndFeedSurvivesJSON() throws {
    let stream = OnlineStream(
      url: URL(string: "https://media.example.com/a.m4a")!, headers: ["Referer": "https://www.bilibili.com/"],
      audioOnly: true, expires: Timestamp(millisecondsSince1970: 1_800_000_000_000))
    let transcript = try Transcript(
      language: "en", origin: .recognized(.base),
      segments: [try .init(start: .zero, end: .seconds(1), text: "Hi", speaker: 1)], speakerNames: [1: "Maya"])
    let page = MediaPage(
      transcript: transcript, translations: [try Translation(language: "zh-Hans", lines: ["你好"])],
      outline: try Outline(chapters: []), hasCover: true, downloaded: false)
    let setup = MediaSetup(
      components: [
        ComponentStatus(component: .ytDlp, installation: .system(path: "/opt/homebrew/bin/yt-dlp", version: nil))
      ],
      componentWork: [
        ComponentWork(component: .ffmpeg, state: .running(Fraction(0.3))),
        ComponentWork(component: .quickJS, state: .failed("HTTP 404")),
      ],
      speechModels: [
        SpeechModelStatus(model: .base, state: .transferring(.running(nil))),
        SpeechModelStatus(model: .tiny, state: .ready),
      ],
      speechModel: .base, browserLogin: .safari)

    #expect(try Self.roundTrips(Playback.online(stream)))
    #expect(try Self.roundTrips(Playback.downloaded))
    #expect(try Self.roundTrips(MediaFileInfo(byteCount: 1 << 33, fileExtension: "mp4")))
    #expect(try Self.roundTrips(page))
    #expect(try Self.roundTrips(setup))
    #expect(
      try Self.roundTrips(
        Feed<[Job]>.value([Job(item: Fixture.item, stage: .download, state: .paused(progress: Fraction(0.5)))])))
    #expect(try Self.roundTrips(Feed<Job?>.value(nil)))
    #expect(try Self.roundTrips(Optional(Data("jpeg".utf8))))
  }

  @Test func librarySubscriptionsListenOnlyForTheirOwnChanges() {
    let other = EntityID(canonical: "019a8f1c-87b8-7fed-b346-6f8a7b81a989")!
    #expect(ItemMedia(item: Fixture.item).isAffected(by: [.job(Fixture.item)]))
    #expect(!ItemMedia(item: Fixture.item).isAffected(by: [.job(other)]))
    #expect(ItemJob(item: Fixture.item).isAffected(by: [.job(Fixture.item)]))
    #expect(AllJobs().isAffected(by: [.job(other)]))
    #expect(MediaSettings().isAffected(by: [.media]))
    #expect(!MediaSettings().isAffected(by: [.job(Fixture.item)]))
  }
}
