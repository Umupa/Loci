import AppKit
import LociModel
import PDFKit
import SwiftUI
import Testing

@testable import LociUI

@MainActor
@Suite(.onStage)
struct MermaidTests {
  static let flowchart = """
    flowchart TB
        SDK["SDK / 客户端<br/>Sandbox.create()、run(cmd)"]
        subgraph CP["控制面（集群级）"]
          API["API：鉴权、配额"]
          SCHED["调度：选节点"]
          STATE[("状态存储<br/>Redis / PostgreSQL")]
        end
        subgraph NODE["计算节点（每台物理机）"]
          AGENT["节点代理<br/>Cubelet / orchestrator / worker"]
          VMM["VMM 进程（用户态）<br/>Firecracker / CubeHypervisor"]
          KVM["KVM（宿主机内核模块）"]
          STORE["存储：rootfs 与内存文件<br/>写时复制"]
          NET["网络：TAP、netns、<br/>出网策略"]
          subgraph VM["MicroVM（一个沙箱）"]
            GK["Guest 内核"]
            GA["Guest agent<br/>envd 等"]
            P["用户代码"]
          end
        end
        OBJ[("对象存储<br/>模板、快照")]
        PROXY["入口代理<br/>port-sandbox.domain"]

        SDK --> API --> SCHED --> AGENT
        API --- STATE
        AGENT --> VMM --> KVM
        VMM --> VM
        AGENT --- STORE
        AGENT --- NET
        STORE <--> OBJ
        SDK -. 命令与文件 .-> PROXY -.-> GA --> P
    """ + "\n"
  static let invalid = "flowchart TB\n  A[\"unfinished\n"

  @Test func diagramLabelsAndSavedQuotesSurviveRenderingWithoutNetworkAccess() async throws {
    let markdown = "前面。\n\n```mermaid\n\(Self.flowchart)```\n\n后面。"
    let initial = ReadingText(markdown: markdown)
    #expect(initial.mermaidSources == [Self.flowchart])
    let images = await MermaidRenderer.render([Self.invalid, Self.flowchart], dark: false)
    let image = try #require(images[Self.flowchart])
    #expect(images[Self.invalid] == nil)
    let pdf = try #require(image.representations.first as? NSPDFImageRep)
    let labels = try #require(
      PDFDocument(data: pdf.pdfRepresentation)?.string?.precomposedStringWithCompatibilityMapping)
    #expect(labels.contains("Sandbox.create()"))
    #expect(labels.contains("MicroVM"))
    #expect(labels.contains("用户代码"))

    let rendered = ReadingText(markdown: markdown, diagrams: images)
    #expect(rendered.plain == "前面。\n\u{FFFC}\n后面。")
    #expect(rendered.original == initial.original)
    #expect(rendered.range(of: try TextQuote("后面。")) != nil)
    #expect(rendered.range(of: try TextQuote("flowchart TB"))?.length == 1)
    let failed = ReadingText(markdown: "```mermaid\n\(Self.invalid)```", diagrams: images)
    #expect(failed.plain == Self.invalid.trimmingCharacters(in: .newlines))

    let (coordinator, scroll, window) = ReaderTests.reader(heard: ReaderTests.Heard())
    defer { window.orderOut(nil) }
    coordinator.show(rendered, from: nil)
    let reader = try #require(scroll.documentView as? ReaderTextView)
    let attachment = (rendered.plain as NSString).range(of: "\u{FFFC}")
    func size(at width: CGFloat) throws -> CGSize {
      window.setContentSize(CGSize(width: width, height: 640))
      let manager = try #require(reader.textLayoutManager)
      let storage = try #require(reader.contentStorage)
      manager.ensureLayout(for: storage.documentRange)
      let range = try #require(reader.textRange(attachment))
      let fragment = try #require(manager.textLayoutFragment(for: range.location))
      return fragment.frameForTextAttachment(at: range.location).size
    }
    let wide = try size(at: 750)
    let narrow = try size(at: 420)
    #expect(narrow.width > 0 && narrow.width < wide.width)
    #expect(narrow.height > 0 && narrow.height < wide.height)
  }

  @Test func aDiagramAppearsWithoutReplacingTextAddedWhileItWasRendering() async throws {
    let sample = try Sample(problems: false)
    let editing = EditingMermaid()
    defer { editing.finish([:]) }
    let host = NSHostingView(
      rootView: EditingMermaidReader(editing: editing, item: sample.borg.id)
        .lociHost(FakeHost(sample)))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 680, height: 700), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await eventually("the new paragraph while the diagram is pending", within: .seconds(5)) {
      editing.pending != nil && Self.reader(in: host)?.string.contains(EditingMermaid.newParagraph) == true
    }
    let image = NSImage(size: CGSize(width: 80, height: 60), flipped: false) { _ in true }
    editing.finish([Self.flowchart: image])
    try await eventually("the diagram to replace its source", within: .seconds(5)) {
      Self.reader(in: host)?.string.contains("\u{FFFC}") == true
    }
    #expect(Self.reader(in: host)?.string.contains(EditingMermaid.newParagraph) == true)
  }

  static func reader(in view: NSView) -> ReaderTextView? {
    if let reader = view as? ReaderTextView { return reader }
    return view.subviews.lazy.compactMap { Self.reader(in: $0) }.first
  }
}

@MainActor
@Observable
private final class EditingMermaid {
  static let newParagraph = "This paragraph arrived while the diagram was being drawn."
  var markdown = "```mermaid\n\(MermaidTests.flowchart)```"
  private(set) var pending: CheckedContinuation<[String: NSImage], Never>?

  func render(_ sources: [String], dark: Bool) async -> [String: NSImage] {
    markdown += "\n\n" + Self.newParagraph
    return await withCheckedContinuation { pending = $0 }
  }

  func finish(_ images: [String: NSImage]) {
    pending?.resume(returning: images)
    pending = nil
  }
}

private struct EditingMermaidReader: View {
  let editing: EditingMermaid
  let item: EntityID

  var body: some View {
    ContentReader(content: .item(item), title: nil, markdown: editing.markdown, renderMermaid: editing.render)
  }
}

@MainActor
@Suite(.onStage)
struct MermaidSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func anArticleRendersMermaidInTheReader(appearance: Snapshot.Appearance) async throws {
    let sample = try Sample(problems: false)
    let view = ContentReader(
      content: .item(sample.borg.id), title: nil,
      markdown: "## 一个沙箱系统由哪几层组成\n\n```mermaid\n\(MermaidTests.flowchart)```\n\n继续读正文。", serif: true
    )
    .lociHost(FakeHost(sample))
    let file = try await Snapshot.render(
      view, named: "reader-mermaid", size: CGSize(width: 680, height: 1280), appearance: appearance,
      until: { window in
        window.contentView.flatMap(MermaidTests.reader(in:))?.string.contains("\u{FFFC}") == true
      })
    #expect(try Data(contentsOf: file).count > 20_000)
  }

}
