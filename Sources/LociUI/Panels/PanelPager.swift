import LociModel
import SwiftUI

/// Pages turned with the arrows either side of the page's name; the new page slides in from the side turned to.
struct PanelPager: View {
  let pages: [PanelPage]
  let actions: PanelActions
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var index: Int
  @State private var turn = PageTurn.forward

  init(pages: [PanelPage], actions: PanelActions, page: Int = 0) {
    self.pages = pages
    self.actions = actions
    _index = State(initialValue: page)
  }

  var body: some View {
    let shown = min(index, max(pages.count - 1, 0))
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        arrow(Symbols.back, label: "panels.previous", to: shown - 1)
        Spacer(minLength: Spacing.xs)
        Text(verbatim: pages.indices.contains(shown) ? pages[shown].name : "")
          .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
          .transaction { $0.animation = nil }
        Spacer(minLength: Spacing.xs)
        arrow(Symbols.forward, label: "panels.next", to: shown + 1)
      }
      .padding(.top, -2)
      .padding(.bottom, Spacing.s)
      .panelRow()
      if pages.indices.contains(shown) {
        PanelRows(rows: pages[shown].rows, actions: actions)
          .id(shown)
          .transition(
            .asymmetric(
              insertion: .offset(x: turn == .forward ? 24 : -24).combined(with: .opacity), removal: .identity))
      }
    }
  }

  private func arrow(_ symbol: String, label: String.LocalizationValue, to page: Int) -> some View {
    Button {
      turn = PageTurn(from: index, to: page)
      withAnimation(reduceMotion ? nil : .timingCurve(0.28, 0.67, 0.32, 1, duration: 0.38)) { index = page }
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Palette.ink)
        .frame(width: Spacing.l, height: Spacing.l)
        .background(Palette.ink.opacity(0.06), in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .disabled(!pages.indices.contains(page))
    .opacity(pages.indices.contains(page) ? 1 : 0.35)
    .accessibilityLabel(Text(.loci(label)))
  }
}
