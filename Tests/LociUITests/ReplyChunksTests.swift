import AppKit
import SwiftUI
import Testing

@testable import LociUI

@MainActor
struct ReplyChunksTests {
  private static let reply = """
    开头一段，带行内公式 $x^2$ 和 `code`。

    ## 第一节

    这一节的第一段。

    - 一
    - 二

    列表之后的一段。

    ```python
    print("hi")
    ```

    代码之后的一段。

    ```math
    x_1 + x_2
    ```

    公式之后的一段。

    ```math
    a+b
    ```

    - 公式之后的列表

    > 引用

    引用之后的一段。

    | 甲 | 乙 |
    | --- | --- |
    | 1 | 2 |

    表格之后的一段。

    ### 第二节
    紧跟标题的一段。
    """

  @Test func aReplyIsCutAtItsHeadingsAndParagraphs() {
    let chunks = ReplyChunks(Self.reply).chunks

    #expect(chunks.map(\.markdown.first) == ["开", "#", "列", "代", "`", "公", "`", "-", "引", "#"])
    #expect(
      chunks.map(\.opening) == [.other, .heading, .other, .other, .other, .other, .other, .other, .other, .heading])
    #expect(chunks.map(\.isFormula) == [false, false, false, false, true, false, true, false, false, false])
    #expect(chunks.map(\.markdown).joined(separator: "\n") == Self.reply)
  }

  @Test func codeListsAndLinkReferencesAreNotCut() {
    #expect(ReplyChunks("```\n\nA\n\n# B\n```").chunks.count == 1)
    #expect(ReplyChunks("1. a\n\n2. b\n\n   c").chunks.count == 1)
    #expect(ReplyChunks("见 [文档][1]。\n\n下一段\n\n[1]: https://example.com").chunks.count == 1)
  }

  @Test func aReplyCutIntoPiecesLinesUpWithTheWholeReply() async throws {
    let whole = try await Self.lines(ReplyChunk(markdown: Self.reply).frame(maxWidth: .infinity, alignment: .leading))
    let cut = try await Self.lines(VStack(spacing: 0) { ReplyText(text: Self.reply, streaming: false) })

    #expect(cut.count == whole.count)
    #expect(zip(cut, whole).allSatisfy { abs($0 - $1) <= 1.5 })
  }

  /// Where each line of text begins, from the top, in points.
  private static func lines(_ view: some View) async throws -> [CGFloat] {
    let host = NSHostingView(rootView: view.frame(width: 380).fixedSize(horizontal: false, vertical: true))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 380, height: 1200), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .seconds(1))
    host.setFrameSize(host.fittingSize)
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsHigh) / host.bounds.height
    var starts: [CGFloat] = []
    var inked = false
    for y in 0..<bitmap.pixelsHigh {
      let row = stride(from: 0, to: bitmap.pixelsWide, by: 2).contains { x in
        (bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).map {
          $0.alphaComponent > 0.4 && $0.brightnessComponent < 0.7
        }
          ?? false
      }
      if row && !inked { starts.append(CGFloat(y) / scale) }
      inked = row
    }
    return starts
  }
}
