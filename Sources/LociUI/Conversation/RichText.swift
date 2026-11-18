import SwiftUI
import Textual

/// Markdown said by a mentor, rendered by Textual: paragraphs, lists, code with highlighting, tables and
/// formulas. It is drawn again as the text grows, so a streaming reply can use it.
struct RichText: View {
  let markdown: String
  var font = Typography.reading

  var body: some View {
    StructuredText(markdown: DisplayMath.fenced(markdown), syntaxExtensions: [.math])
      .font(font)
      .foregroundStyle(Palette.ink)
      .textual.codeBlockStyle(CopyableCodeBlock())
      .textual.structuredTextStyle(.default)
      .textual.textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
