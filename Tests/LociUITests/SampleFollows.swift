import Foundation
import LociModel

@testable import LociUI

/// The follows the design draws: three channels over the videos, two shows over the podcasts, each with its
/// episodes, some new since it was last opened and one already in the library.
enum SampleFollows {
  static let opened = Timestamp(millisecondsSince1970: 1_764_000_000_000)
  static let day: Int64 = 86_400_000

  static func picture(_ name: String) -> URL? { URL(string: "https://pictures.example/\(name).jpg") }

  static func time(_ days: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: opened.millisecondsSince1970 + days * day)
  }

  static func id(_ seed: UInt64) -> EntityID {
    EntityID("019ac000-0000-7000-8000-\(String(format: "%012d", seed))") ?? EntityID()
  }

  static func video(_ id: String, _ title: String, days: Int64, minutes: Int, picture: String) -> Episode {
    Episode(
      title: title, link: URL(string: "https://www.youtube.com/watch?v=\(id)") ?? URL(filePath: "/"),
      published: time(days), length: .seconds(minutes * 60 + 17), picture: Self.picture(picture))
  }

  static func episode(_ number: Int, _ title: String, days: Int64, minutes: Int) -> Episode {
    Episode(
      title: "\(number). \(title)",
      link: URL(string: "https://www.xiaoyuzhoufm.com/episode/ep\(number)") ?? URL(filePath: "/"),
      published: time(days), length: .seconds(minutes * 60))
  }

  static func follow(_ seed: UInt64, _ name: String, handle: String?, picture: String, channel: Bool) -> Follow {
    Follow(
      id: id(seed), source: channel ? .youtube(channel: "UC\(seed)") : .xiaoyuzhou(podcast: "p\(seed)", apple: nil),
      name: name, handle: handle, picture: Self.picture(picture),
      page: URL(string: "https://www.youtube.com/@sample\(seed)") ?? URL(filePath: "/"), followed: time(-90),
      opened: opened)
  }

  static func page(
    _ follow: Follow, _ episodes: [Episode], fresh: Int, kept: [Int: EntityID] = [:],
    problem: FollowProblem? = nil
  ) -> FollowPage {
    FollowPage(
      follow: follow,
      entries: episodes.enumerated().map { index, episode in
        FollowPage.Entry(
          episode: episode, firstSeen: index < fresh ? time(1) : follow.followed, item: kept[index])
      },
      problem: problem)
  }

  static func pages(keeping item: EntityID) -> [FollowPage] {
    let cncf = follow(1, "CNCF", handle: "@cncf", picture: "kube", channel: true)
    let plumbers = follow(2, "Linux Plumbers", handle: "@linuxplumbers", picture: "uring", channel: true)
    let oxide = follow(3, "Oxide Computer", handle: "@oxidecomputer", picture: "oxide", channel: true)
    let latent = follow(4, "Latent Space", handle: nil, picture: "latent", channel: false)
    let log = follow(5, "商业访谈录", handle: nil, picture: "log", channel: false)
    return [
      page(
        cncf,
        [
          video("a1", "Kueue: Batch Scheduling Comes to Kubernetes", days: 1, minutes: 38, picture: "kueue"),
          video("a2", "etcd Internals: How Raft Keeps the Cluster Honest", days: 0, minutes: 52, picture: "etcd"),
          video("a3", "Scheduling at Scale: Inside the Kubernetes Scheduler", days: -4, minutes: 34, picture: "kube"),
          video("a4", "eBPF Beyond Networking", days: -12, minutes: 27, picture: "ebpf"),
          video("a5", "Firecracker in Production", days: -20, minutes: 44, picture: "firecracker-microvm-firecracker"),
        ], fresh: 2, kept: [2: item]),
      page(
        plumbers,
        [video("b1", "io_uring: Faster I/O with Fewer System Calls", days: -3, minutes: 41, picture: "uring")],
        fresh: 0),
      page(
        oxide,
        [video("c1", "The Rack as a Computer", days: -9, minutes: 61, picture: "oxide")], fresh: 1),
      page(
        latent,
        [
          episode(201, "The State of AI Engineering, Winter 2026", days: 1, minutes: 73),
          episode(200, "Why Inference Is Eating the Data Center", days: -6, minutes: 72),
          episode(199, "Agents at Work: Evals, Memory and Cost", days: -13, minutes: 64),
          episode(198, "Tokenizers Are Not Boring", days: -20, minutes: 58),
        ], fresh: 1, problem: .refused),
      page(
        log,
        [
          episode(158, "和沈驿康聊：年终复盘、持续学习与创业地图", days: -2, minutes: 203),
          episode(157, "复盘 Personal Agent：AI 产品史、需求真伪与入口", days: -9, minutes: 164),
          episode(156, "对影之刃零梁其伟 6 小时访谈", days: -14, minutes: 360),
        ], fresh: 0),
    ]
  }

  static let preview = FollowPreview(
    source: .youtube(channel: "UC9"), name: "GPU MODE", handle: "@GPUMODE", picture: picture("attention"),
    page: URL(string: "https://www.youtube.com/@GPUMODE") ?? URL(filePath: "/"),
    episodes: [
      video("d1", "Lecture 123: Larger Fusions and Consistent RL", days: 0, minutes: 66, picture: "attention"),
      video("d2", "Lecture 122: Mercury Multi-GPU Operator Optimization", days: -7, minutes: 53, picture: "tokenizer"),
      video("d3", "Lecture 121: Building a Tokenizer on the GPU", days: -14, minutes: 48, picture: "late"),
    ])
}
