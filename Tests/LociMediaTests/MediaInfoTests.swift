import Foundation
import LociModel
import Testing

@testable import LociMedia

struct MediaInfoTests {
  @Test func aYouTubeVideoGivesItsTitleChannelChaptersAndSubtitles() throws {
    let info = try MediaInfo(json: try Fixture.data("youtube"))

    #expect(info.title == "Me at the zoo")
    #expect(info.site == "jawed")
    #expect(info.duration == .seconds(19))
    #expect(info.published == Date(timeIntervalSince1970: 1_114_313_512))
    #expect(info.thumbnail?.host() == "i.ytimg.com")
    #expect(info.chapters.map(\.title) == ["Intro", "The cool thing", "End"])
    #expect(info.chapters.map(\.start) == [.zero, .seconds(5), .seconds(17)])
    #expect(info.subtitleLanguage == "en")
    #expect(!info.isAudio)
  }

  @Test func aVideoWithPictureAndSoundInOneMP4PlaysThatWhileDownloading() throws {
    let info = try MediaInfo(json: try Fixture.data("youtube"))

    let stream = try #require(info.stream)
    #expect(!stream.audioOnly)
    #expect(stream.expires == Timestamp(millisecondsSince1970: 1_794_956_995_000))
  }

  @Test func aBilibiliVideoWithSeparateStreamsPlaysItsSoundFirst() throws {
    let info = try MediaInfo(json: try Fixture.data("bilibili"))

    #expect(info.title == "【官方 MV】Never Gonna Give You Up - Rick Astley")
    #expect(info.site == "索尼音乐中国")
    #expect(info.thumbnail?.scheme == "https")
    let stream = try #require(info.stream)
    #expect(stream.audioOnly)
    #expect(stream.headers["Referer"] == "https://www.bilibili.com/video/BV1GJ411x7h7")
    #expect(info.subtitleLanguage == nil)
  }

  @Test func anApplePodcastsEpisodeIsSoundFromItsShow() throws {
    let info = try MediaInfo(json: try Fixture.data("apple-podcasts"))

    #expect(info.title == "Finally, a Vaccine for Cancer")
    #expect(info.site == "The Daily")
    #expect(info.duration == .seconds(1358))
    #expect(info.isAudio)
    #expect(info.stream?.audioOnly == true)
    #expect(info.stream?.url.pathExtension == "mp3")
  }

  @Test func aXiaoyuzhouEpisodeFoundByTheGenericReaderHasNoSiteButPlays() throws {
    let info = try MediaInfo(json: try Fixture.data("xiaoyuzhou"))

    #expect(info.title == "Vol.66 这2023年总算是过完了")
    #expect(info.site == nil)
    #expect(info.duration == nil)
    #expect(info.isAudio)
    #expect(info.stream?.url.pathExtension == "m4a")
  }

  @Test func subtitlesAreChosenInTheSpokenLanguage() {
    #expect(MediaInfo.subtitleLanguage(["de", "en"], language: "de-DE", title: "x") == "de")
    #expect(MediaInfo.subtitleLanguage(["de", "en"], language: nil, title: "How the scheduler works") == "en")
    #expect(MediaInfo.subtitleLanguage(["zh-Hans", "en"], language: nil, title: "调度器是怎样工作的") == "zh-Hans")
    #expect(MediaInfo.subtitleLanguage(["ja", "danmaku"], language: nil, title: "x") == "ja")
    #expect(MediaInfo.subtitleLanguage(["danmaku"], language: nil, title: "x") == nil)
  }

  @Test func somethingThatIsNotYtDlpJSONIsAnError() {
    #expect(throws: MediaError.self) { try MediaInfo(json: Data("not json".utf8)) }
    #expect(throws: MediaError.self) { try MediaInfo(json: Data("{}".utf8)) }
  }
}
