import SwiftUI

/// The button beside the panels' that lays the main page out at once: panels on the right, on the left, on
/// both sides, or the conversation alone. Each choice is drawn, not named.
struct LayoutButton: View {
  @Binding var layout: TalkLayout
  @Binding var panelsShown: Bool
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var open = false
  @State private var pointed = false

  var body: some View {
    Button {
      open.toggle()
    } label: {
      Image(systemName: Symbols.layout)
        .font(.system(size: 14))
        .foregroundStyle(pointed || open ? Palette.ink : Palette.inkMuted)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(pointed || open ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .onHover { pointed = $0 }
    .help(Text(.loci("talk.layout")))
    .accessibilityLabel(Text(.loci("talk.layout")))
    .popover(isPresented: $open, arrowEdge: .bottom) {
      HStack(spacing: Spacing.xs) {
        ForEach(Choice.all, id: \.self) { choice in
          Button {
            choose(choice)
          } label: {
            LayoutGlyph(choice: choice, chosen: chosen == choice)
          }
          .buttonStyle(PressStyle(scale: 0.95))
          .accessibilityLabel(Text(choice.name))
        }
      }
      .padding(10)
    }
  }

  enum Choice: Hashable {
    case arranged(TalkLayout.Arrangement)
    case conversationAlone

    static let all: [Choice] = TalkLayout.Arrangement.allCases.map(Choice.arranged) + [.conversationAlone]

    var name: LocalizedStringResource {
      switch self {
      case .arranged(.panelsRight): .loci("talk.panelsRight")
      case .arranged(.panelsLeft): .loci("talk.panelsLeft")
      case .arranged(.panelsBothSides): .loci("talk.panelsBothSides")
      case .conversationAlone: .loci("talk.conversationAlone")
      }
    }
  }

  private var chosen: Choice? {
    guard panelsShown else { return .conversationAlone }
    return layout.arrangement.map(Choice.arranged)
  }

  private func choose(_ choice: Choice) {
    withAnimation(reduceMotion ? nil : Motion.standard) {
      switch choice {
      case .arranged(let arrangement):
        panelsShown = true
        layout = layout.arranged(arrangement)
      case .conversationAlone:
        panelsShown = false
      }
    }
  }
}

/// A choice of layout drawn small: the conversation as a paper block, panel lanes as faint ones.
private struct LayoutGlyph: View {
  let choice: LayoutButton.Choice
  let chosen: Bool
  @State private var pointed = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
    HStack(spacing: 4) {
      switch choice {
      case .arranged(.panelsRight):
        conversation
        lane
      case .arranged(.panelsLeft):
        lane
        conversation
      case .arranged(.panelsBothSides):
        lane
        conversation
        lane
      case .conversationAlone:
        Spacer(minLength: 10)
        conversation
        Spacer(minLength: 10)
      }
    }
    .padding(7)
    .frame(width: 76, height: 54)
    .background(chosen ? Palette.tint : pointed ? Palette.fill : .clear, in: shape)
    .overlay(shape.strokeBorder(chosen ? Palette.accent : Palette.lineStrong, lineWidth: chosen ? 1.5 : Size.hairline))
    .contentShape(shape)
    .onHover { pointed = $0 }
  }

  private var conversation: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(Palette.surface)
      .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 0.5))
      .layoutPriority(1)
      .frame(minWidth: 26)
  }

  private var lane: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.lineStrong).frame(maxWidth: 16)
  }
}
