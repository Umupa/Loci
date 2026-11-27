import LociModel
import SwiftUI

/// The changes of several versions, newest first, each version named beside its changes. It is as tall as
/// they are, up to `tallest`, and scrolls beyond that.
struct ReleaseChanges: View {
  let notes: [ReleaseNotes]
  static let tallest: CGFloat = 320
  @State private var height: CGFloat = 0

  var body: some View {
    ScrollView {
      Rows(notes: notes)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          height = $0
        }
    }
    .frame(height: min(height, Self.tallest))
  }

  struct Rows: View {
    let notes: [ReleaseNotes]

    var body: some View {
      VStack(alignment: .leading, spacing: Spacing.s) {
        ForEach(notes, id: \.version) { note in
          HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(note.version.description)
              .font(Typography.caption.monospacedDigit())
              .foregroundStyle(Palette.inkMuted)
              .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.xs) {
              ForEach(Array(note.changes.enumerated()), id: \.offset) { _, change in
                Text(ReleaseChanges.inline(change))
                  .font(Typography.body)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .textSelection(.enabled)
    }
  }

  /// A change's inline Markdown, such as `code` and bold, or the words as written when it does not parse.
  static func inline(_ change: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: change, options: options)) ?? AttributedString(change)
  }
}
