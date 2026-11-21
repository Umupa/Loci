import SwiftUI
import Textual

/// Markdown said by Loci, rendered by Textual: paragraphs, lists, code with highlighting, tables and
/// formulas. It is drawn again as the text grows, so a streaming reply can use it.
struct RichText: View {
  /// How tables are ruled: a full grid, or a page's single line under the header.
  enum Tables {
    case grid, headerRule
  }

  let markdown: String
  var font = Typography.reading
  var tables = Tables.grid

  var body: some View {
    let text = StructuredText(markdown: DisplayMath.fenced(markdown), syntaxExtensions: [.math])
    Group {
      switch tables {
      case .grid: text
      case .headerRule: text.textual.tableStyle(HeaderRuleTable())
      }
    }
    .font(font)
    .foregroundStyle(Palette.ink)
    .textual.codeBlockStyle(CopyableCodeBlock())
    .textual.structuredTextStyle(.default)
    .textual.textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .followsPointerForCode()
  }
}

/// A table with no lines but one under its header, as a page sets it.
private struct HeaderRuleTable: StructuredText.TableStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .textual.tableCellSpacing(horizontal: 0, vertical: 0)
      .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 1.6))
      .textual.tableOverlay { layout in
        Canvas { context, _ in
          guard layout.numberOfRows > 1 else { return }
          let header = layout.rowBounds(0)
          context.fill(
            Path(CGRect(x: layout.bounds.minX, y: header.maxY, width: layout.bounds.width, height: Size.hairline)),
            with: .color(Palette.ink.opacity(0.25)))
        }
      }
  }
}
