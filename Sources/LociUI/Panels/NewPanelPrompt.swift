import SwiftUI

/// Something a panel could follow, offered in the empty composer while it asks for a new panel.
struct PanelExample {
  let words: LocalizedStringResource
  let sources: PanelSources

  static let all = [
    PanelExample(words: .loci("panels.exampleReleases"), sources: PanelSources(sites: ["github.com"])),
    PanelExample(
      words: .loci("panels.exampleReads"), sources: PanelSources(sites: ["news.ycombinator.com"], loci: true)),
    PanelExample(words: .loci("panels.exampleJobs"), sources: PanelSources(sites: ["notion.so"])),
    PanelExample(words: .loci("panels.examplePeople"), sources: PanelSources(sites: ["x.com"])),
  ]

  /// How long each example stays before the next rises in.
  static let stay = Duration.milliseconds(2600)

  /// The example shown `turns` turns after the first.
  static func at(_ turns: Int) -> PanelExample {
    all[turns % all.count]
  }
}

/// The examples in turn, each rising in as the last rises away.
struct PanelExamples: View {
  let index: Int
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    Text(PanelExample.at(index).words).font(.system(size: 15)).foregroundStyle(Palette.ink.opacity(0.45))
      .lineLimit(1)
      .id(index)
      .transition(
        reduceMotion
          ? .identity
          : .asymmetric(
            insertion: .offset(y: Spacing.s).combined(with: .opacity),
            removal: .offset(y: -Spacing.s).combined(with: .opacity)))
  }
}

/// The round button left of the composer that stops asking for a new panel.
struct NewPanelCancel: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.undo)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(Palette.ink)
        .frame(width: Size.composerHeight, height: Size.composerHeight)
        .background {
          Circle().fill(.ultraThinMaterial)
          Circle().fill(Palette.composerGlass)
        }
        .overlay(Circle().strokeBorder(Palette.composerEdge, lineWidth: Size.hairline))
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .accessibilityLabel(Text(.loci("panels.cancelNew")))
  }
}
