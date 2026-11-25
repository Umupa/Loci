import LociModel
import SwiftUI

/// The field at the top of each library page. A link pasted or typed in adds on Return; the button beside it
/// chooses files on this Mac. The link icon turns amber once the field holds a link.
struct LinkField: View {
  let category: LibraryCategory?
  let add: (URL) -> Void
  let chooseFiles: () -> Void
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var text = ""

  var body: some View {
    let prompt = Text(Self.prompt(for: category))
    HStack(spacing: Spacing.s) {
      Image(systemName: Symbols.link)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(Self.link(in: text) == nil ? Palette.inkFaint : Palette.accent)
        .accessibilityHidden(true)
      TextField(text: $text, prompt: prompt.foregroundStyle(Palette.inkFaint)) { prompt }
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .onSubmit(submit)
      Button(action: chooseFiles) {
        HStack(spacing: 6) {
          Image(systemName: Symbols.folder).font(.system(size: 12, weight: .medium))
          Text(.loci("link.files"))
        }
        .font(Typography.control)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 12)
        .frame(height: Size.linkField - 12)
        .background(Capsule().fill(Palette.fill))
        .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        .contentShape(Capsule())
      }
      .buttonStyle(PressStyle())
    }
    .padding(.leading, 18)
    .padding(.trailing, 6)
    .frame(height: Size.linkField)
    .background(Capsule().fill(Palette.surface))
    .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .disabled(!changesAllowed)
  }

  private func submit() {
    guard let link = Self.link(in: text) else { return }
    text = ""
    add(link)
  }

  /// The link in what was typed or pasted: the text itself, or the one link in words shared along with it,
  /// as apps do when sharing a video.
  static func link(in text: String) -> URL? {
    Dropped.link(in: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  static func prompt(for category: LibraryCategory?) -> LocalizedStringResource {
    switch category {
    case .video: .loci("link.promptVideo")
    case .audio: .loci("link.promptAudio")
    case .article: .loci("link.promptArticle")
    case .book: .loci("link.promptBook")
    case nil: .loci("link.prompt")
    }
  }
}
