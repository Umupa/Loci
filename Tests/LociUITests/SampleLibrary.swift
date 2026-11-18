import AppKit
import Foundation
import LociModel

@testable import LociUI

/// The library the design draws: three mentors, a dozen items in every state, the video, podcast and
/// article it opens, and the media settings.
struct SampleLibrary: Sendable {
  let system: Mentor
  let scheduling: Mentor
  let network: Mentor
  let items: [Item]
  let covers: [EntityID: String]
  let jobs: [Job]
  let states: [EntityID: ReadingState]
  let video: Item
  let podcast: Item
  let article: Item
  let attention: Item
  var setup: MediaSetup
  /// Lets later parts of the sample number their messages and notes after the items.
  var entropy = Sample.Seeded(state: 99)

  var mentors: [Mentor] { [system, scheduling, network] }

  /// `empty` keeps the mentors and drops every item.
  init(empty: Bool = false) throws {
    var entropy = Sample.Seeded(state: 1234)
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_000_000 + offset), entropy: &entropy)
    }
    system = try Self.mentor(id(1), "系统底层", "hello 背后的调用链", 0xE8734A, .ember)
    scheduling = try Self.mentor(id(2), "调度", "Kubernetes 调度", 0x4F7FD9, .north)
    network = try Self.mentor(id(3), "网络", "网络", 0x3E9C84, .iris)
    func link(_ text: String) -> URL? { URL(string: text) }
    func minutes(_ text: String) -> Duration {
      .seconds(text.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) })
    }
    video = try Item(
      id: id(10), kind: .video(duration: minutes("34:12")),
      title: "Scheduling at Scale: Inside the Kubernetes Scheduler",
      authors: ["KubeCon NA 2025"], source: link("https://www.youtube.com/watch?v=O_zcc6XI12g"), language: "en",
      site: "CNCF")
    podcast = try Item(
      id: id(11), kind: .audio(duration: minutes("1:12:03")), title: "Why Inference Is Eating the Data Center",
      source: link("https://www.latent.space/p/inference"), language: "en", site: "Latent Space")
    attention = try Item(
      id: id(12), kind: .article, title: "Attention Is All You Need", authors: ["Vaswani et al."],
      source: link("https://arxiv.org/abs/1706.03762"), site: "arxiv.org")
    article = try Item(
      id: id(15), kind: .article,
      title: "How we built Pingora, the proxy that connects Cloudflare to the Internet",
      authors: ["Yuchen Wu", "Andrew Hauck"],
      source: link(
        "https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet/"),
      language: "en", site: "blog.cloudflare.com",
      published: Timestamp(Date(timeIntervalSince1970: 1_663_113_600)))
    let uring = try Item(
      id: id(13), kind: .video(duration: minutes("41:27")), title: "io_uring: Faster I/O with Fewer System Calls",
      site: "Linux Plumbers")
    let late = try Item(
      id: id(14), kind: .audio(duration: minutes("1:03:45")), title: "大模型推理成本是怎么降下来的", site: "晚点聊")
    let ebpf = try Item(id: id(16), kind: .video(duration: minutes("28:16")), title: "图解 eBPF：从内核探针到可观测性", site: "哔哩哔哩")
    let tokenizer = try Item(
      id: id(17), kind: .video(duration: minutes("2:13:35")), title: "Let's build the GPT Tokenizer",
      site: "Andrej Karpathy")
    let kleppmann = try Item(
      id: id(18), kind: .video(duration: minutes("46:58")), title: "Turning the Database Inside Out",
      site: "Strange Loop")
    let log = try Item(
      id: id(19), kind: .article,
      title: "The Log: What every software engineer should know about real-time data's unifying abstraction",
      site: "engineering.linkedin.com")
    let oxide = try Item(
      id: id(20), kind: .audio(duration: minutes("58:20")), title: "Rack-scale power-on, one year later",
      site: "Oxide and Friends")
    let gregg = try Item(
      id: id(21), kind: .video(duration: minutes("52:41")), title: "Linux Systems Performance", site: "USENIX")
    let all = [video, podcast, attention, uring, late, article, ebpf, tokenizer, kleppmann, log, oxide, gregg]
    items = empty ? [] : all
    covers = [
      video.id: "kube", podcast.id: "latent", attention.id: "attention", uring.id: "uring", late.id: "late",
      article.id: "pingora", ebpf.id: "ebpf", tokenizer.id: "tokenizer", kleppmann.id: "kleppmann", log.id: "log",
      oxide.id: "oxide", gregg.id: "gregg",
    ]
    jobs = [
      Job(item: uring.id, stage: .download, state: .running(progress: Fraction(0.42))),
      Job(item: late.id, stage: .transcribe, state: .running(progress: Fraction(0.63))),
      Job(item: ebpf.id, stage: .resolve, state: .waiting(.component(.ytDlp))),
      Job(item: tokenizer.id, stage: .transcribe, state: .waiting(.speechModel(.largeV3TurboQuantized))),
      Job(
        item: kleppmann.id, stage: .resolve,
        state: .failed(Job.Failure(reason: "YouTube refused the request", remedy: .updateComponent(.ytDlp)))),
    ]
    func at(_ item: Item, _ share: Double, updated: Int) throws -> ReadingState {
      let start = (item.length ?? .seconds(100)) * share
      return ReadingState(
        position: .item(item.id, .time(try TimeSpan(start: start))), finished: false,
        updatedAt: Timestamp(millisecondsSince1970: 1_763_337_600_000 + Int64(updated) * 1000))
    }
    states = [
      video.id: try at(video, 680.0 / 2052, updated: 30),
      podcast.id: try at(podcast, 1101.0 / 4323, updated: 20),
      attention.id: ReadingState(
        position: .item(attention.id, .quote(try TextQuote("Scaled Dot-Product Attention"))), finished: false,
        updatedAt: Timestamp(millisecondsSince1970: 1_763_337_610_000)),
      late.id: try at(late, 0.08, updated: 1).unshelved,
      oxide.id: ReadingState(
        position: nil, finished: true, updatedAt: Timestamp(millisecondsSince1970: 1_763_337_600_000)),
    ]
    setup = MediaSetup(
      components: [
        ComponentStatus(
          component: .ytDlp, installation: .system(path: "/opt/homebrew/bin/yt-dlp", version: "2026.10.26")),
        ComponentStatus(component: .ffmpeg, installation: .managed(version: "9.0.2")),
        ComponentStatus(component: .quickJS, installation: .managed(version: "0.18.0")),
      ],
      componentWork: [],
      speechModels: SpeechModel.allCases.map { model in
        let state: SpeechModelStatus.State =
          switch model {
          case .tiny, .largeV3TurboQuantized: .ready
          case .medium: .transferring(.running(Fraction(0.38)))
          default: .absent
          }
        return SpeechModelStatus(model: model, state: state)
      }, speechModel: .largeV3TurboQuantized, browserLogin: .none)
  }

  func cover(of item: EntityID) -> Data? {
    guard let name = covers[item] else { return nil }
    return Self.picture(name)
  }

  /// A picture drawn from the design for the tests, by name.
  static func picture(_ name: String) -> Data? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures/Covers") else {
      return nil
    }
    return try? Data(contentsOf: url)
  }

  private static func mentor(
    _ id: EntityID, _ name: String, _ course: String, _ color: UInt32, _ mark: Mentor.Mark
  ) throws -> Mentor {
    try Mentor(
      id: id, name: name, avatar: mark.rawValue,
      color: MentorColor(red: UInt8(color >> 16 & 0xFF), green: UInt8(color >> 8 & 0xFF), blue: UInt8(color & 0xFF)),
      provider: .pi, request: course)
  }
}

extension ReadingState {
  /// The same place, but long enough ago that the item is not on the shelf.
  fileprivate var unshelved: ReadingState {
    ReadingState(position: position, finished: finished, updatedAt: Timestamp(millisecondsSince1970: 0))
  }
}
