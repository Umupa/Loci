import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// A lesson the way Loci writes one: headings, prose with inline code, a list, a quote, a comparison table, a
/// diagram and a code block, set as a course sets it.
@MainActor
@Suite(.onStage)
struct LessonPageSnapshots {
  static let markdown = """
    # 三个沙箱项目怎么分层

    一个沙箱系统要回答三个问题：代码跑在哪里、状态记在哪里、请求怎么进来。CubeSandbox、E2B 和 SPACE 给出的答案大同小异，差别都藏在**每一层的取舍**里。

    ## 一张表看清每一层

    | 层 | CubeSandbox（腾讯云） | E2B runtime | SPACE（Perplexity） |
    | --- | --- | --- | --- |
    | 语言 | Go + Rust | Go | Rust（shim 用 Go） |
    | 控制面状态 | 无状态，Redis | PostgreSQL + Redis | PostgreSQL 记录期望状态，控制器对账 |
    | VMM | CubeHypervisor（Cloud Hypervisor 的 fork，以库的形式跑在 CubeShim 进程里） | Firecracker（独立进程） | Firecracker（独立进程） |
    | 宿主机 ↔ guest agent | vsock（cube-agent） | 网络直连 VM 内的 envd（端口 49983） | vsock（宿主侧 spaced-host） |
    | 内存恢复 | 快照恢复 + 增量脏页 | `userfaultfd` 按缺页懒加载 | 快照恢复（suspend/wake） |

    三家都用 KVM 做隔离，真正拉开差距的是**恢复速度**：冷启动一个 MicroVM 要几百毫秒，从快照恢复只要几十毫秒。

    ## 请求怎么走到沙箱里

    ```mermaid
    flowchart LR
        SDK["SDK"] --> API["API：鉴权、配额"] --> SCHED["调度"] --> AGENT["节点代理"]
        AGENT --> VMM["VMM 进程"] --> VM["MicroVM"]
        API --- STATE[("Redis / PostgreSQL")]
        SDK -. 命令与文件 .-> PROXY["入口代理"] -.-> VM
    ```

    ### 为什么控制面要无状态

    - 节点代理掉线时，控制面能从存储里重建期望状态。
    - 扩容只需要多起几个 API 实例，不需要选主。
    - 代价是每次调度都要读一次 Redis。

    > 一个经验：凡是能从节点上报里重建的状态，都不要放在控制面的内存里。

    ```go
    func (s *Scheduler) Pick(req Request) (*Node, error) {
        return s.nodes.LeastLoaded(req.Memory)
    }
    ```

    最后一段正文，看看段落之间的节奏是否舒服，长句换行后行距是否足够，中英文混排时 Firecracker 和 vsock 这样的词是否和汉字对齐。
    """

  @Test(arguments: Snapshot.Appearance.allCases)
  func aLessonReadsLikeAPage(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let view = ContentReader(content: .item(sample.borg.id), title: nil, markdown: Self.markdown)
      .background(Palette.canvas)
      .lociHost(FakeHost(sample))
    let file = try await Snapshot.render(
      view, named: "reader-lesson", size: CGSize(width: 820, height: 1900), appearance: appearance,
      until: { window in
        (window.contentView.flatMap(MermaidTests.reader(in:))?.string.filter { $0 == "\u{FFFC}" }.count ?? 0) >= 2
      })
    #expect(try Data(contentsOf: file).count > 20_000)
  }
}
