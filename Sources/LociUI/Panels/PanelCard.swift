import LociModel
import SwiftUI

/// A panel's frame: its sites' marks and title over what it shows, cut off at `panelTallest` with the foot
/// fading out. Pointing at a panel that is cut off shows the button that opens it out.
struct PanelFrame<Marks: View, Content: View>: View {
  let title: Text
  let menu: [PanelMenu]
  let choose: (PanelMenu) -> Void
  @ViewBuilder var marks: Marks
  @ViewBuilder var content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var open: Bool
  @State private var height: CGFloat = 0
  @State private var pointed = false

  /// `open` starts the panel opened out, for a snapshot.
  init(
    title: Text, menu: [PanelMenu], open: Bool = false, choose: @escaping (PanelMenu) -> Void,
    @ViewBuilder marks: () -> Marks, @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.menu = menu
    self.choose = choose
    self.marks = marks()
    self.content = content()
    _open = State(initialValue: open)
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    let cut = height > Size.panelTallest && !open
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.bottom, 14)
      content
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, Spacing.xxs)
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      height = $0
    }
    .frame(height: cut ? Size.panelTallest : nil, alignment: .top)
    .overlay(alignment: .bottom) {
      if cut {
        LinearGradient(colors: [Palette.surface.opacity(0), Palette.surface], startPoint: .top, endPoint: .bottom)
          .frame(height: 70)
          .allowsHitTesting(false)
      }
    }
    .background(Palette.surface)
    .clipShape(shape)
    .overlay(shape.strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline))
    .contentShape(shape)
    .onHover { pointed = $0 }
    .contextMenu {
      ForEach(menu, id: \.self) { entry in
        if entry == .moveToTop, menu.count > 1 { Divider() }
        Button {
          choose(entry)
        } label: {
          Text(entry.name)
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: Spacing.xs) {
      marks
      title.font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
      Spacer(minLength: 0)
      if height > Size.panelTallest {
        OpenOutButton(open: open) {
          withAnimation(reduceMotion ? nil : Motion.standard) { open.toggle() }
        }
        .opacity(pointed || open ? 1 : 0)
        .scaleEffect(pointed || open ? 1 : 0.85)
        .animation(reduceMotion ? nil : Motion.quick, value: pointed)
      }
    }
    .frame(height: Size.siteMark)
  }
}

private struct OpenOutButton: View {
  let open: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: open ? Symbols.collapse : Symbols.openOut)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(Palette.ink.opacity(0.07), in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .accessibilityLabel(Text(.loci(open ? "panels.close" : "panels.open")))
  }
}

/// A panel Loci keeps. When Loci rewrites it, the new rows fade in over the old.
struct PanelCard: View {
  let panel: Panel
  var refreshing = false
  let actions: PanelActions
  var open = false
  var page = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    PanelFrame(
      title: Text(verbatim: panel.title), menu: PanelMenu.entries(for: .panel(panel)), open: open, choose: choose
    ) {
      SiteBadges(sites: panel.sources)
    } content: {
      ZStack(alignment: .topLeading) {
        shown.id(panel.body).transition(.opacity)
      }
      .opacity(refreshing ? 0.5 : 1)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: panel.body)
      .animation(reduceMotion ? nil : Motion.quick, value: refreshing)
    }
  }

  @ViewBuilder private var shown: some View {
    switch panel.body {
    case .rows(let rows): PanelRows(rows: rows, actions: actions)
    case .pages(let pages): PanelPager(pages: pages, actions: actions, page: page)
    }
  }

  private func choose(_ entry: PanelMenu) {
    switch entry {
    case .refresh: actions.refresh(panel)
    case .revise: actions.revise(panel)
    case .moveToTop: actions.moveToTop(.panel(panel))
    case .remove: actions.remove(panel)
    }
  }
}

/// Pages turned with the arrows either side of the page's name; the new page slides in from the side turned to.
struct PanelPager: View {
  let pages: [PanelPage]
  let actions: PanelActions
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
