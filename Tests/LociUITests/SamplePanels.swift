import AppKit
import Foundation
import LociModel

@testable import LociUI

/// The panels the design draws beside the main conversation: 「接着读」, two that page, one list, and the one
/// made while the design plays.
enum SamplePanels {
  static func readingNow() throws -> [ReadingNow] {
    var entropy = Sample.Seeded(state: 4321)
    func item(_ offset: Double, _ kind: Item.Kind, _ title: String, site: String) throws -> Item {
      let id = EntityID(at: Date(timeIntervalSince1970: 1_763_100_000 + offset), entropy: &entropy)
      return try Item(id: id, kind: kind, title: title, site: site)
    }
    return [
      ReadingNow(
        item: try item(1, .article, "Firecracker 逃逸链复盘", site: "PWN Research"), progress: 0.64, minutesLeft: 12),
      ReadingNow(
        item: try item(2, .article, "Kata 4.4 发布说明与 vsock 改动", site: "kata-containers"), progress: 0.22,
        minutesLeft: 18),
      ReadingNow(
        item: try item(3, .audio(duration: .seconds(3600)), "E2B 的沙箱是怎么在 150ms 里启动的", site: "Latent Space"),
        progress: 0.4, minutesLeft: 36),
    ]
  }

  /// The cover of an item read partway, by item.
  static func cover(of item: EntityID) -> Data? {
    let names = ["firecracker-microvm-firecracker", "kata-containers-kata-containers", "e2b-dev-infra"]
    guard let readings = try? readingNow(), let index = readings.firstIndex(where: { $0.item.id == item }) else {
      return nil
    }
    return SampleLibrary.picture(names[index])
  }

  static let radar = Panel(
    name: "sandbox-radar", title: "沙箱雷达", sources: ["github.com", "news.ycombinator.com"],
    follow: "盯着 CubeSandbox 的新版本、PR 和可以认领的 issue，再看看沙箱赛道",
    refresh: PanelRefresh(every: .hour),
    body: .pages([
      PanelPage(
        name: "CubeSandbox",
        rows: [
          .sentence("**v0.8.0** 正式版发布，**你的 PR #2214** 在里面。"),
          .cells([
            PanelCell(label: "最新版本", value: "v0.8.0", note: "8 天前"),
            PanelCell(label: "24h 合并 / 新 issue", value: "11 / 6"),
          ]),
          .label("最近合并"),
          .list([
            PanelListItem(
              title: "#2360 fix(tests): 保持快照恢复存活", subtitle: "lkml-likexu", at: "昨天",
              link: URL(string: "https://github.com/tencentcloud/CubeSandbox/pull/2360")),
            PanelListItem(title: "#2348 feat(configs): 为客户机内核启用 DAMON_RECLAIM", subtitle: "Gong-qg", at: "昨天"),
            PanelListItem(title: "#2352 fix(cubelet): 沙箱仍在运行时清除重启计数", subtitle: "fslongjin", at: "昨天"),
          ]),
          .label("可以认领"),
          .list([
            PanelListItem(
              title: "#244 文档：主流 Agent 框架集成指南", subtitle: "good first issue",
              ask: "帮我分析 CubeSandbox #244：要改哪些地方，我能怎么贡献"),
            PanelListItem(title: "#243 文档：补充使用案例", subtitle: "good first issue", ask: "帮我分析 CubeSandbox #243"),
          ]),
        ]),
      PanelPage(
        name: "沙箱赛道",
        rows: [
          .sentence("**外部沙箱** 成了编程 Agent 的新方向。"),
          .label("本周新增 star"),
          .bars([
            PanelBar(name: "e2b-dev/E2B", fraction: 1, value: "+1.2k"),
            PanelBar(name: "microsandbox", fraction: 0.62, value: "+740"),
            PanelBar(name: "CubeSandbox", fraction: 0.41, value: "+490"),
            PanelBar(name: "kata-containers", fraction: 0.18, value: "+210"),
          ]),
          .label("竞品发布"),
          .list([
            PanelListItem(title: "Kata Containers 4.4.0", subtitle: "kata-containers/kata-containers", at: "周二"),
            PanelListItem(title: "gVisor release-20261116.0", subtitle: "google/gvisor", at: "周一"),
          ]),
        ]),
    ]))

  static let feed = Panel(
    name: "following", title: "关注精选", sources: ["x.com"], follow: "我关注的人今天在 X 上说了什么",
    refresh: PanelRefresh(every: .day, at: "08:00"),
    body: .rows([
      .sentence("**@poteto** 转发 Bombadil 0.8.0，模糊测试快了 4 倍。"),
      .list([
        PanelListItem(title: "@poteto", subtitle: "转发：Bombadil 0.8.0 浏览器模糊测试快 4 倍", at: "昨天"),
        PanelListItem(title: "@jiayuan_jy", subtitle: "Harness 不是护城河，模型才是", at: "昨天"),
        PanelListItem(title: "@huacnlee", subtitle: "NSH TSX：一次写完跨平台麻将", at: "昨天"),
        PanelListItem(title: "@object_nulll", subtitle: "连接器本地化的几个坑", at: "昨天"),
      ]),
    ]))

  static let jobs = Panel(
    name: "job-radar", title: "岗位雷达", sources: ["notion.so"], follow: "Notion 岗位库里有新岗位就告诉我",
    refresh: PanelRefresh(every: .day, at: "09:00"),
    body: .pages([
      PanelPage(
        name: "腾讯混元",
        rows: [
          .sentence("**混元沙盒** 和你的 CubeSandbox 经验最对口。"),
          .prominent(title: "腾讯 TEG｜混元沙盒平台工程师", subtitle: "北京 / 深圳 / 上海 · 1 年以上"),
          .list([
            PanelListItem(title: "大规模 CPU 沙箱与弹性虚拟环境"), PanelListItem(title: "VM 与容器统一编排、网络代理隔离"),
            PanelListItem(title: "镜像、快照、状态恢复与可复现回放"),
          ]),
        ]),
      PanelPage(
        name: "阿里云",
        rows: [
          .sentence("**函数计算沙箱** 要 Firecracker 经验，正好接上你这周读的。"),
          .prominent(title: "阿里云｜Serverless 安全容器研发", subtitle: "杭州 · 3 年以上"),
          .list([
            PanelListItem(title: "Firecracker / Kata 安全容器"), PanelListItem(title: "冷启动优化与快照"),
            PanelListItem(title: "多租户网络隔离"),
          ]),
        ]),
    ]))

  /// The panel made while the design plays, with a picture and covers the design leaves to this one.
  static let reads = Panel(
    name: "sandbox-reads", title: "沙箱好文", sources: ["news.ycombinator.com", "simonwillison.net"],
    follow: "每周挑三篇沙箱相关的好文章", refresh: PanelRefresh(every: .week, at: "10:00", weekday: 1),
    body: .rows([
      .sentence("这周三篇，第一篇讲 **AWS Nitro Sandboxes**。"),
      .list([
        PanelListItem(
          title: "AWS 推出 Nitro Sandboxes，让容器拥有独立 VM 边界", subtitle: "cloudnativenow.com · HN 212 分", number: 1,
          link: URL(string: "https://cloudnativenow.com/nitro-sandboxes"), ask: "这篇和 Firecracker 的做法差在哪"),
        PanelListItem(
          title: "编程 Agent 的外部沙箱", subtitle: "simonwillison.net · HN 188 分", number: 2,
          ask: "帮我读这篇，挑出和 CubeSandbox 有关的"),
        PanelListItem(
          title: "gVisor 的系统调用拦截，五年后回头看", subtitle: "blog.primeradiant.com · HN 96 分", number: 3,
          ask: "用三句话讲讲 gVisor 的取舍"),
      ]),
      .label("封面"),
      .list([
        PanelListItem(
          title: "Firecracker: Lightweight Virtualization", subtitle: "usenix.org",
          cover: picture("firecracker-microvm-firecracker"),
          progress: 0.3)
      ]),
      .picture(picture("e2b-dev-infra"), link: nil),
    ]))

  static func picture(_ name: String) -> URL {
    URL(string: "https://pictures.example/\(name).jpg")!
  }

  static func column(reads: Bool = true, refreshing: Set<String> = []) throws -> PanelColumn {
    PanelColumn(
      slots: [.reading(try readingNow()), .panel(radar), .panel(feed), .panel(jobs)]
        + (reads ? [.panel(Self.reads)] : []),
      refreshing: refreshing)
  }
}
