import Foundation
import LociModel

@testable import LociUI

/// The panels the editable-panels design draws: a week's to-dos, promises Loci noted, and the sandbox radar
/// with lines the person pinned, noted and hid.
enum SampleItemPanels {
  static func item(
    _ id: String, _ text: String, by: PanelItem.Author = .you, proposed: Bool = false, done: Bool = false,
    pinned: Bool = false, note: String? = nil, why: String? = nil
  ) -> PanelItem {
    PanelItem(id: id, text: text, by: by, proposed: proposed, done: done, pinned: pinned, note: note, why: why)
  }

  static func week(allDone: Bool = false) -> Panel {
    Panel(
      name: "week", title: "本周待办", follow: "这周要做的事",
      body: .rows([
        .items(
          PanelItems(
            id: "today", name: "今天", adds: true, checks: true,
            items: [
              item("escape", "读完《Firecracker 逃逸链复盘》", done: allDone),
              item("notes", "整理沙箱隔离的面试笔记", by: .loci, done: allDone, why: "你昨天说想在周四前过一遍"),
              item("cat", "买猫粮", done: true),
            ])),
        .items(
          PanelItems(
            id: "week", name: "本周", adds: true, checks: true,
            items: [
              item("kata", "周五前回 Kata vsock 的 review", by: .loci),
              item("bench", "CubeSandbox 冷启动压测", pinned: true),
              item("e2b", "给 E2B 的 issue 补一个复现", note: "先在 4.4 上试"),
            ])),
      ]))
  }

  static let promises = Panel(
    name: "promises", title: "答应过的事", follow: "我在对话里答应别人的事",
    body: .rows([
      .items(
        PanelItems(
          id: "all", adds: true, checks: true,
          items: [
            item("lin", "下周一给 Lin 回面试时间", by: .loci, proposed: true),
            item("resume", "帮阿哲看简历", by: .loci, proposed: true),
            item("blog", "周末把博客草稿发给编辑"),
          ]))
    ]))

  static let radar = Panel(
    name: "radar", title: "沙箱雷达", sources: ["github.com", "news.ycombinator.com", "x.com"],
    follow: "盯着沙箱赛道的讨论和发布", refresh: PanelRefresh(every: .day, at: "10:00"),
    body: .rows([
      .sentence("**Docker Sandboxes** 引发 HN 讨论，firecracker 合并了增量恢复。"),
      .list([
        PanelListItem(
          title: "HN 热议：Docker Sandboxes 其实不是容器", subtitle: "HN 7 分 · 43 条评论", at: "周六",
          link: URL(string: "https://news.ycombinator.com/item?id=46100")),
        PanelListItem(
          title: "firecracker#4921 合并 snapshot 增量恢复", subtitle: "firecracker-microvm", at: "昨天",
          link: URL(string: "https://github.com/firecracker-microvm/firecracker/pull/4921")),
        PanelListItem(title: "kata-containers 4.4 发布说明", subtitle: "vsock 握手改动", at: "昨天"),
        PanelListItem(title: "@liyue_ai：GPT 6.2 Astra 网站走红", subtitle: "28.2 万浏览", at: "2 天前"),
      ]),
    ]))

  static let marks: [String: [PanelLineKey: PanelLineMark]] = [
    "radar": [
      PanelLineKey(rawValue: "https://github.com/firecracker-microvm/firecracker/pull/4921"):
        PanelLineMark(pinned: true, note: "和 CubeSandbox 的快照对比一下"),
      PanelLineKey(rawValue: "@liyue_ai：GPT 6.2 Astra 网站走红"): PanelLineMark(hidden: true),
    ]
  ]

  static func slots(allDone: Bool = false) -> [PanelSlot] {
    [.panel(week(allDone: allDone)), .panel(radar), .panel(promises)]
  }
}
