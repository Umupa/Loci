import LociModel
import SwiftUI

/// Where translating an article stands, as the reader shows it.
struct ArticleLanguage: Equatable {
  let translation: ArticleTranslation?
  let progress: TranslationProgress?

  /// The translation to set the text with in `mode`, once any of it has arrived.
  func shown(_ mode: SubtitleMode) -> ShownTranslation? {
    translation.map { ShownTranslation(passages: $0.bySource, mode: mode) }
  }
}

/// The translate button in the top corner of an article in another language. Before there is a translation it
/// asks for one; once there is, it chooses between the original, both, and the translation. A ring fills while
/// the passages arrive.
struct TranslateButton: View {
  let language: ArticleLanguage
  @Binding var mode: SubtitleMode
  let translate: () -> Void
  @State private var hovering = false

  var body: some View {
    Group {
      if language.translation == nil {
        Button {
          mode = .both
          translate()
        } label: {
          face
        }
        .buttonStyle(PressStyle())
        .disabled(running)
      } else {
        Menu {
          Picker(selection: $mode) {
            ForEach(SubtitleMode.allCases, id: \.self) { Text($0.name).tag($0) }
          } label: {
            EmptyView()
          }
          .pickerStyle(.inline)
          if case .failed = language.progress {
            Divider()
            Button(action: translate) { Text(.loci("article.translateAgain")) }
          }
        } label: {
          face
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PressStyle())
        .fixedSize()
      }
    }
    .onHover { hovering = $0 }
    .help(Text(help))
    .accessibilityLabel(Text(help))
  }

  private var face: some View {
    ZStack {
      if case .running(let share) = language.progress {
        Circle().stroke(Palette.line, lineWidth: 1.5)
        Circle()
          .trim(from: 0, to: max(share.value, 0.04))
          .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      Image(systemName: failed ? Symbols.retry : Symbols.translate)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(hovering || shownTranslated ? Palette.ink : Palette.inkMuted)
    }
    .padding(2)
    .frame(width: Size.iconButton, height: Size.iconButton)
    .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fillStrong : .clear))
    .contentShape(Rectangle())
  }

  private var running: Bool {
    if case .running = language.progress { true } else { false }
  }

  private var failed: Bool {
    if case .failed = language.progress { true } else { false }
  }

  private var shownTranslated: Bool { language.translation != nil && mode != .original }

  private var help: LocalizedStringResource {
    switch language.progress {
    case .running: .loci("article.translating")
    case .failed(let reason): .loci("article.translationFailed \(reason)")
    case nil: language.translation == nil ? .loci("article.translate") : .loci("article.languages")
    }
  }
}
