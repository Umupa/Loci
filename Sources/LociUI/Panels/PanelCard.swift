import LociModel
import SwiftUI

/// A panel's frame: its sites' marks and title over what it shows. A panel taller than `panelTallest` is cut
/// where a row ends, never through one, with a round button under it that opens it out and folds it back.
struct PanelFrame<Marks: View, Content: View>: View {
  let title: Text
  let menu: [PanelMenu]
  let choose: (PanelMenu) -> Void
  @ViewBuilder var marks: Marks
  @ViewBuilder var content: Content
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var open: Bool
  @State private var height: CGFloat = 0
  @State private var edges: [CGFloat] = []

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
    let long = PanelCut.isLong(height)
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.bottom, 14)
      content
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(.named(PanelRowEdges.space))
        .onPreferenceChange(PanelRowEdges.self) { edges = $0 }
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          height = $0
        }
        .frame(height: long && !open ? PanelCut.height(edges: edges) : nil, alignment: .top)
        .clipped()
      if long {
        OpenOutButton(open: open) {
          withAnimation(reduceMotion ? nil : Motion.standard) { open.toggle() }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.s)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, Spacing.xxs)
    .background(Palette.surface)
    .clipShape(shape)
    .overlay(shape.strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline))
    .contentShape(shape)
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
    }
    .frame(height: Size.siteMark)
  }
}

/// Where a long panel is cut: at the lowest row's end that still fits.
enum PanelCut {
  /// How much taller than `panelTallest` a panel must be before it is cut, so it never hides a sliver.
  static let slack: CGFloat = 40

  static func isLong(_ height: CGFloat) -> Bool {
    height > Size.panelTallest + slack
  }

  static func height(edges: [CGFloat]) -> CGFloat {
    edges.filter { $0 <= Size.panelTallest }.max() ?? Size.panelTallest
  }
}

/// Where each row of a panel ends, measured from the top of its rows.
struct PanelRowEdges: PreferenceKey {
  static let space = "panelRows"
  static let defaultValue: [CGFloat] = []

  static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
    value += nextValue()
  }
}

extension View {
  /// Lets a long panel be cut where this row ends.
  func panelRow() -> some View {
    background {
      GeometryReader { proxy in
        Color.clear.preference(key: PanelRowEdges.self, value: [proxy.frame(in: .named(PanelRowEdges.space)).maxY])
      }
    }
  }
}

/// The round button under a cut panel: a chevron that turns over once the panel is open.
private struct OpenOutButton: View {
  let open: Bool
  let action: () -> Void
  @State private var pointed = false

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.openPanel)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(pointed ? Palette.ink : Palette.inkMuted)
        .rotationEffect(.degrees(open ? 180 : 0))
        .frame(width: 44, height: 22)
        .background(Palette.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        .shadow(color: Palette.liftShadow.opacity(0.35), radius: 5, y: 3)
        .contentShape(.capsule)
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .onHover { pointed = $0 }
    .padding(.top, Spacing.xxs)
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
  @Environment(\.reducesMotion) private var reduceMotion

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
