import Foundation
import LociMedia
import LociModel
import Synchronization

/// Reads follows from what the test set: each source's newest episodes, its past ones, or why it fails.
/// Remembers how often each source was read.
final class ScriptedFollows: FollowReading {
  struct Show: Sendable {
    var preview: FollowPreview
    var latest: [Episode]
    var past: [Episode] = []
    var failure: FollowFailure?
  }

  private let shows = Mutex<[String: Show]>([:])
  private let looks = Mutex<[String]>([])

  /// The shows by the identity of their source.
  func set(_ show: Show) {
    shows.withLock { $0[show.preview.source.identity] = show }
  }

  func change(_ source: FollowSource, _ change: @Sendable (inout Show) -> Void) {
    shows.withLock { shows in
      if var show = shows[source.identity] {
        change(&show)
        shows[source.identity] = show
      }
    }
  }

  /// How many times each source's newest episodes were read.
  func reads(of source: FollowSource) -> Int {
    looks.withLock { $0.count { $0 == source.identity } }
  }

  func preview(_ link: FollowLink) async throws(FollowFailure) -> FollowPreview {
    guard
      let show = shows.withLock({ $0.values.first { link.leads(to: $0.preview.source) || link.url == $0.preview.page } }
      )
    else { throw FollowFailure(.gone, "no such show") }
    if let failure = show.failure { throw failure }
    return show.preview
  }

  func latest(_ source: FollowSource) async throws(FollowFailure) -> [Episode] {
    looks.withLock { $0.append(source.identity) }
    guard let show = shows.withLock({ $0[source.identity] }) else { throw FollowFailure(.gone, "no such show") }
    if let failure = show.failure { throw failure }
    return show.latest
  }

  func past(_ follow: Follow, ytDlp: YtDlp?) async throws(FollowFailure) -> [Episode] {
    guard let show = shows.withLock({ $0[follow.source.identity] }) else { throw FollowFailure(.gone, "no such show") }
    if let failure = show.failure { throw failure }
    return show.past + show.latest
  }

  func show(ofEpisode link: URL) async throws(FollowFailure) -> FollowLink? {
    try await FollowReader(network: NoNetwork()).show(ofEpisode: link)
  }
}

private struct NoNetwork: Network {
  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    throw FetchError(reason: "no network here")
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no network here")
  }
}

enum FollowSamples {
  static let channel = URL(string: "https://www.youtube.com/channel/UCdwarkesh")!
  static let show = URL(string: "https://podcasts.apple.com/podcast/id1634356920")!

  static func video(_ id: String, day: Int64, title: String? = nil) -> Episode {
    Episode(
      title: title ?? "Video \(id)", link: URL(string: "https://www.youtube.com/watch?v=\(id)")!,
      published: Timestamp(millisecondsSince1970: TestWorld.instant.millisecondsSince1970 + day * 86_400_000))
  }

  static func episode(_ id: Int, day: Int64) -> Episode {
    Episode(
      title: "\(id). 访谈", link: URL(string: "https://podcasts.apple.com/podcast/x/id1634356920?i=\(id)")!,
      published: Timestamp(millisecondsSince1970: TestWorld.instant.millisecondsSince1970 + day * 86_400_000))
  }

  static let dwarkesh = ScriptedFollows.Show(
    preview: FollowPreview(
      source: .youtube(channel: "UCdwarkesh"), name: "Dwarkesh Patel", handle: "@DwarkeshPatel", page: channel,
      episodes: [video("c", day: -1), video("b", day: -8), video("a", day: -15)]),
    latest: [video("c", day: -1), video("b", day: -8), video("a", day: -15)],
    past: [video("old", day: -40)])

  static let zhang = ScriptedFollows.Show(
    preview: FollowPreview(
      source: .apple(1_634_356_920), name: "张小珺Jùn｜商业访谈录", page: show,
      episodes: [episode(158, day: -3), episode(157, day: -10)]),
    latest: [episode(158, day: -3), episode(157, day: -10)])
}
