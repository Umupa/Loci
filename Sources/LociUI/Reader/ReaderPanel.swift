import AppKit
import LociModel
import SwiftUI

/// The pages of the side column beside text.
enum SideTab: Hashable {
  case keyPoints, conversation, highlights
}

/// Beside an item or a lesson: an item's key points, Loci reading along with the conversation on it, or every
/// highlight left on it.
struct ReaderPanel: View {
  let content: ContentRef
  let notes: [PlacedNote]
  let keyPoints: KeyPointsPage?
  /// `nil` for what has no key points, such as a paper; the panel then has no page for them.
  let openKeyPoint: ((KeyPoint) -> Void)?
  @Binding var tab: SideTab
  @Binding var draft: PassageDraft?
  /// The highlight chosen last, and a serial that changes each time it is chosen again.
  let chosen: ChosenNote?
  let reveal: (NSRange) -> Void
  let revealPassage: @MainActor (Locator) -> Void
  let ask: (PlacedNote) -> Void
  let collapse: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      CompanionHeader(
        tab: $tab, tabs: (openKeyPoint == nil ? [] : [(.keyPoints, .loci("panel.keyPoints"))]) + Self.tabs,
        collapse: collapse)
      switch tab {
      case .keyPoints:
        if let item = content.item {
          KeyPointsPanel(item: item, media: nil, page: keyPoints, current: nil, frames: nil) { openKeyPoint?($0) }
        }
      case .conversation:
        ConversationScreen(
          ref: content.conversation, draft: $draft, revealPassage: revealPassage, lesson: content.lesson)
      case .highlights:
        highlights
      }
    }
    .background(Palette.canvas)
    .overlay(alignment: .leading) {
      Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline)
    }
  }

  private static let tabs: [(value: SideTab, title: LocalizedStringResource)] = [
    (.conversation, .loci("panel.conversation")), (.highlights, .loci("panel.highlights")),
  ]

  private var highlights: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Spacing.xs) {
          ForEach(notes) { placed in
            NoteCard(
              content: content, placed: placed, chosen: chosen?.note == placed.id ? chosen?.serial : nil,
              ask: placed.range == nil ? nil : { ask(placed) }
            ) {
              if let range = placed.range { reveal(range) }
            }
            .id(placed.id)
          }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.bottom, Spacing.l)
      }
      .scrollIndicators(.never)
      .onChange(of: chosen) { _, chosen in
        if let chosen { withAnimation(Motion.standard) { proxy.scrollTo(chosen.note, anchor: .center) } }
      }
    }
  }
}

/// A highlight chosen in the text, so its card comes into view and flashes; a new serial does it again.
struct ChosenNote: Equatable {
  let note: EntityID
  let serial: Int
}

/// The square button that folds the panel away, or brings it back.
struct PanelButton: View {
  let title: LocalizedStringResource
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.panel)
        .font(.system(size: 14))
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .help(Text(title))
    .accessibilityLabel(Text(title))
  }
}
