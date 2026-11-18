import AppKit
import LociModel
import SwiftUI

/// The pages of the panel beside text.
enum PanelTab: Hashable {
  case conversation, highlights
}

/// Beside the text: the conversation with its mentor, or every highlight left on it. Text with no mentor
/// shows only its highlights.
struct ReaderPanel<Extra: View>: View {
  let content: ContentRef
  let mentor: Mentor?
  let conversation: Conversation?
  /// An item's conversation, read along with the mentor chosen at its top.
  var companion: CompanionPanel?
  let notes: [PlacedNote]
  @Binding var tab: PanelTab
  @Binding var draft: PassageDraft?
  /// The highlight chosen last, and a serial that changes each time it is chosen again.
  let chosen: ChosenNote?
  let reveal: (NSRange) -> Void
  let revealPassage: @MainActor (Locator) -> Void
  let ask: (PlacedNote) -> Void
  let collapse: () -> Void
  /// Shown under the highlights, such as where the text comes from.
  @ViewBuilder let extra: () -> Extra
  @State private var mentors: Feed<[Mentor]>?

  var body: some View {
    VStack(spacing: 0) {
      header
      if let companion, tab == .conversation {
        CompanionThread(
          item: companion.item, conversation: companion.conversation, mentors: companion.mentors, draft: $draft,
          revealPassage: revealPassage)
      } else if let mentor, tab == .conversation {
        ConversationScreen(mentor: mentor, conversation: conversation, draft: $draft, revealPassage: revealPassage)
      } else {
        highlights
      }
    }
    .background(Palette.well)
    .overlay(alignment: .leading) {
      Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline)
    }
    .subscribing(AllMentors(), into: $mentors)
  }

  private var header: some View {
    ZStack {
      if mentor != nil || companion != nil {
        CapsulePicker(
          selection: $tab,
          options: [(.conversation, .loci("panel.conversation")), (.highlights, .loci("panel.highlights"))])
      }
      HStack {
        Spacer()
        PanelButton(title: .loci("panel.collapse"), action: collapse)
      }
    }
    .padding(.horizontal, Spacing.s)
    .frame(height: Size.panelHeader)
  }

  private var highlights: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Spacing.xs) {
          ForEach(notes) { placed in
            NoteCard(
              content: content, placed: placed, mentors: mentors?.value ?? [],
              chosen: chosen?.note == placed.id ? chosen?.serial : nil,
              ask: mentor == nil && companion == nil || placed.range == nil ? nil : { ask(placed) }
            ) {
              if let range = placed.range { reveal(range) }
            }
            .id(placed.id)
          }
          extra()
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

/// Links under the highlights to what the text draws on or is drawn on by.
struct PanelLinks<Links: View>: View {
  let title: Text
  @ViewBuilder let links: () -> Links

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      SidebarLabel(text: title)
      links()
    }
    .buttonStyle(.plain)
    .font(Typography.body)
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, Spacing.xxs)
    .padding(.top, Spacing.m)
  }
}

/// What the panel needs to hold an item's conversation.
struct CompanionPanel {
  let item: EntityID
  let conversation: ItemConversation?
  let mentors: [Mentor]
}
