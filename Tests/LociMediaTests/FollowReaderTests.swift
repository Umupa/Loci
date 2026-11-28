import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociMedia

/// FO-S1, FO-S6: who a followable link is and its newest episodes are read with plain GETs as no one; what
/// goes wrong is told as the person reads it.
struct FollowReaderTests {
  static let channel = "UCJgIbYl6C5no72a0NUAPcTA"
  static let channelFeed = "https://www.youtube.com/feeds/videos.xml?channel_id=\(channel)"
  static let show = "626b46ea9cbbf0451cf5a962"

  @Test func aYouTubeChannelIsReadFromItsPageAndItsFeed() async throws {
    let network = Pages([
      "https://www.youtube.com/@GPUMODE": .file("follow-youtube-channel", "html"),
      Self.channelFeed: .file("follow-youtube-feed", "xml"),
    ])
    let preview = try await FollowReader(network: network).preview(
      .youtube(try #require(URL(string: "https://www.youtube.com/@GPUMODE"))))

    #expect(preview.source == .youtube(channel: Self.channel))
    #expect(preview.name == "GPU MODE")
    #expect(preview.handle == "@GPUMODE")
    #expect(preview.page.absoluteString == "https://www.youtube.com/@GPUMODE")
    #expect(preview.picture?.host() == "yt3.googleusercontent.com")
    #expect(preview.episodes.count == 3)
    let first = try #require(preview.episodes.first)
    #expect(first.key == EpisodeKey("youtube/jhBF3UaPD2E"))
    #expect(first.title.hasPrefix("Larger Fusions and Consistent RL"))
    #expect(first.published == Timestamp(try #require(try? Date("2026-11-21T08:19:35Z", strategy: .iso8601))))
    #expect(first.picture?.absoluteString == "https://i3.ytimg.com/vi/jhBF3UaPD2E/hqdefault.jpg")
    #expect(network.methods == ["GET", "GET"])
  }

  @Test func aXiaoyuzhouShowIsReadFromItsPageAndFoundOnApple() async throws {
    let network = Pages([
      "https://www.xiaoyuzhoufm.com/podcast/\(Self.show)": .file("follow-xiaoyuzhou-podcast", "html"),
      "https://itunes.apple.com/search": .file("follow-itunes-search", "json"),
    ])
    let preview = try await FollowReader(network: network).preview(.xiaoyuzhou(Self.show))

    #expect(preview.source == .xiaoyuzhou(podcast: Self.show, apple: 1_634_356_920))
    #expect(preview.name == "张小珺Jùn｜商业访谈录")
    #expect(preview.picture?.host() == "image.xyzcdn.net")
    let first = try #require(preview.episodes.first)
    #expect(first.link.absoluteString == "https://www.xiaoyuzhoufm.com/episode/6b05746801b0ab432eddab62")
    #expect(first.length == .seconds(12156))
    #expect(first.title.hasPrefix("158."))
    #expect(network.methods.allSatisfy { $0 == "GET" })
  }

  @Test func aXiaoyuzhouShowsPastEpisodesComeFromAppleAndLeadBackToXiaoyuzhou() async throws {
    let network = Pages(["https://itunes.apple.com/lookup": .file("follow-apple-lookup", "json")])
    let follow = Follow(
      id: EntityID(), source: .xiaoyuzhou(podcast: Self.show, apple: 1_634_356_920), name: "张小珺",
      page: try #require(URL(string: "https://www.xiaoyuzhoufm.com/podcast/\(Self.show)")), followed: Timestamp(.now))

    let past = try await FollowReader(network: network).past(follow, ytDlp: nil)

    #expect(past.count == 4)
    #expect(past.first?.key == EpisodeKey("xiaoyuzhou/6b05746801b0ab432eddab62"))
    #expect(network.asked.first?.query()?.contains("limit=200") == true)
  }

  @Test func anAppleShowIsReadFromTheLookup() async throws {
    let network = Pages(["https://itunes.apple.com/lookup": .file("follow-apple-lookup", "json")])
    let preview = try await FollowReader(network: network).preview(.apple(1_634_356_920))

    #expect(preview.source == .apple(1_634_356_920))
    #expect(preview.name == "张小珺Jùn｜商业访谈录")
    #expect(preview.episodes.count == 4)
    #expect(preview.episodes.first?.length == .seconds(12156))
    #expect(preview.episodes.first?.link.host() == "podcasts.apple.com")
  }

  @Test func aPodcastFeedGivesItsEpisodesWithAudio() async throws {
    let url = "https://example.com/latent.xml"
    let network = Pages([url: .file("follow-podcast-feed", "xml")])
    let preview = try await FollowReader(network: network).preview(.feed(try #require(URL(string: url))))

    #expect(preview.name == "Latent Space")
    #expect(preview.picture?.absoluteString == "https://example.com/latent.jpg")
    #expect(preview.episodes.map(\.title) == ["The State of AI Engineering, Winter 2026", "Agents at Work"])
    #expect(preview.episodes.map(\.length) == [.seconds(4410), .seconds(2710)])
    #expect(preview.episodes[1].link.absoluteString == "https://cdn.example.com/latent-200.mp3")
    #expect(preview.episodes[0].published != nil)
  }

  @Test(arguments: [
    (401, FollowProblem.signIn), (403, .refused), (429, .refused), (404, .gone), (410, .gone), (503, .offline),
  ])
  func whatGoesWrongIsToldAsTheReasonThePersonSees(status: Int, problem: FollowProblem) async throws {
    let network = Pages([Self.channelFeed: .status(status)])
    await #expect(throws: FollowFailure.self) {
      _ = try await FollowReader(network: network).latest(.youtube(channel: Self.channel))
    }
    do {
      _ = try await FollowReader(network: network).latest(.youtube(channel: Self.channel))
    } catch {
      #expect(error.problem == problem)
    }
  }

  @Test func aChannelsPastVideosAreListedByYtDlpWithLengthsAndRoughDates() async throws {
    let listing = try String(decoding: Fixture.data("follow-ytdlp-channel"), as: UTF8.self)
    let runner = ScriptedRunner(output: listing)
    let ytDlp = YtDlp(
      executable: URL(filePath: "/bin/yt-dlp"), ffmpeg: nil, quickJS: nil,
      signIn: .init(browser: .none, cookies: nil), proxy: nil, runner: runner)
    let follow = Follow(
      id: EntityID(), source: .youtube(channel: Self.channel), name: "GPU MODE",
      page: try #require(URL(string: "https://www.youtube.com/@GPUMODE")), followed: Timestamp(.now))

    let past = try await FollowReader(network: Pages([:])).past(follow, ytDlp: ytDlp)

    #expect(past.count == 3)
    #expect(past.allSatisfy { $0.length != nil && $0.published != nil })
    let arguments = try #require(runner.calls.first?.arguments)
    #expect(arguments.contains("--flat-playlist"))
    #expect(arguments.last == "https://www.youtube.com/@GPUMODE/videos")
  }
}

/// Answers GETs from fixtures by the start of their address, and remembers what was asked how.
final class Pages: Network {
  enum Answer: Sendable {
    case file(String, String)
    case status(Int)
  }

  private let answers: [String: Answer]
  private let log = Mutex<[(String, URL)]>([])

  init(_ answers: [String: Answer]) {
    self.answers = answers
  }

  var methods: [String] { log.withLock { $0.map(\.0) } }
  var asked: [URL] { log.withLock { $0.map(\.1) } }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    guard let url = request.url else { throw FetchError(reason: "no address") }
    log.withLock { $0.append((request.httpMethod ?? "GET", url)) }
    guard let answer = answers.first(where: { url.absoluteString.hasPrefix($0.key) })?.value else {
      throw FetchError(reason: "HTTP 404")
    }
    switch answer {
    case .status(let status):
      throw FetchError(reason: "HTTP \(status)", needsLogin: status == 401 || status == 403)
    case .file(let name, let type):
      guard let file = Bundle.module.url(forResource: name, withExtension: type, subdirectory: "Fixtures"),
        let data = try? Data(contentsOf: file),
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
      else { throw FetchError(reason: "no fixture \(name)") }
      return (data, response)
    }
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "a follow never downloads")
  }
}

/// FO-S2: an item's channel or show is found from its link.
struct EpisodeShowTests {
  @Test func anAppleEpisodeNamesItsShowWithoutAsking() async throws {
    let network = Pages([:])
    let link = try #require(URL(string: "https://podcasts.apple.com/us/podcast/x/id1634356920?i=1000803881972"))

    #expect(try await FollowReader(network: network).show(ofEpisode: link) == .apple(1_634_356_920))
    #expect(network.asked.isEmpty)
  }

  @Test func aXiaoyuzhouEpisodeNamesItsShowOnItsPage() async throws {
    let page = "https://www.xiaoyuzhoufm.com/episode/6b05746801b0ab432eddab62"
    let network = Pages([page: .file("follow-xiaoyuzhou-podcast", "html")])

    #expect(
      try await FollowReader(network: network).show(ofEpisode: try #require(URL(string: page)))
        == .xiaoyuzhou("626b46ea9cbbf0451cf5a962"))
  }

  @Test func anArticleHasNoShow() async throws {
    let link = try #require(URL(string: "https://example.com/post"))
    #expect(try await FollowReader(network: Pages([:])).show(ofEpisode: link) == nil)
  }
}
