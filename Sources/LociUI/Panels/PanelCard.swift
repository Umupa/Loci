import AppKit
import LociModel
import SwiftUI

/// A panel's frame keeps whole rows readable and previews the overflow until the panel is opened out.
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
    let overflow = PanelPreview(height: height, rowEnds: edges)
    let preview = open ? nil : overflow
    VStack(alignment: .leading, spacing: 0) {
      header(canOpen: overflow != nil).padding(.bottom, 14)
      content
        .environment(\.panelPreview, preview)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(.named(PanelRowEdges.space))
        .onPreferenceChange(PanelRowEdges.self) { edges = $0 }
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          height = $0
        }
        .frame(height: preview?.height, alignment: .top)
        .clipShape(Rectangle().inset(by: preview == nil ? -Spacing.s : 0))
        .overlay(alignment: .bottom) {
          if let preview {
            LinearGradient(
              stops: [.init(color: .clear, location: 0.4), .init(color: Palette.surface, location: 1)],
              startPoint: .top, endPoint: .bottom
            )
            .frame(height: preview.revealHeight)
            .allowsHitTesting(false)
          }
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

  private func header(canOpen: Bool) -> some View {
    HStack(spacing: Spacing.xs) {
      marks
      title.font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
      Spacer(minLength: 0)
      if canOpen {
        OpenOutButton(open: open) {
          withAnimation(reduceMotion ? nil : Motion.standard) { open.toggle() }
        }
        .transition(.opacity)
      }
    }
    .frame(height: Size.siteMark)
  }
}

/// The boundary between readable rows and the strip hinting at more content.
struct PanelPreview: Equatable {
  private static let slack: CGFloat = 40
  private let clearHeight: CGFloat
  let revealHeight: CGFloat
  var height: CGFloat { clearHeight + revealHeight }

  init?(height: CGFloat, rowEnds: [CGFloat]) {
    guard height > Size.panelTallest + Self.slack, let first = rowEnds.min(), let last = rowEnds.max() else {
      return nil
    }
    let clearHeight = rowEnds.filter { $0 <= Size.panelTallest }.max() ?? first
    guard last > clearHeight else { return nil }
    self.clearHeight = clearHeight
    revealHeight = min(Spacing.l, last - clearHeight)
  }

  func showsRow(endingAt end: CGFloat) -> Bool {
    end <= clearHeight
  }
}

extension EnvironmentValues {
  @Entry fileprivate var panelPreview: PanelPreview?
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
  /// Marks a row that can be shown whole or seen only in the overflow preview.
  func panelRow() -> some View {
    modifier(PanelRowPresentation())
  }
}

private struct PanelRowPresentation: ViewModifier {
  @Environment(\.panelPreview) private var preview
  @State private var bounds: ClosedRange<CGFloat>?

  func body(content: Content) -> some View {
    let shown = preview?.showsRow(endingAt: bounds?.upperBound ?? .infinity) ?? true
    let blurred = !shown && (bounds?.lowerBound ?? .infinity) < (preview?.height ?? 0)
    content
      .blur(radius: blurred ? 3 : 0)
      .opacity(shown || blurred ? 1 : 0)
      .disabled(!shown)
      .allowsHitTesting(shown)
      .accessibilityHidden(!shown)
      .preference(key: PanelRowEdges.self, value: bounds.map { [$0.upperBound] } ?? [])
      .onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
        let frame = proxy.frame(in: .named(PanelRowEdges.space))
        return frame.height > 0 ? frame.minY...frame.maxY : nil
      } action: {
        bounds = $0
      }
  }
}

/// The corner marks beside a cut panel's title: two corners that point out while it is cut and fold in once it
/// is open.
private struct OpenOutButton: View {
  let open: Bool
  let action: () -> Void
  @State private var pointed = false

  var body: some View {
    Button(action: action) {
      OpenOutCorners(folded: open ? 1 : 0)
        .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .foregroundStyle(pointed ? Palette.ink : Palette.inkFaint)
        .frame(width: 14, height: 14)
        .frame(width: Size.iconButton, height: Size.iconButton)
        .background(Palette.ink.opacity(pointed ? 0.06 : 0), in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .onHover { pointed = $0 }
    .accessibilityLabel(Text(.loci(open ? "panels.close" : "panels.open")))
  }
}

/// A top-left and a bottom-right corner. Each corner's ends stay put while its point moves across, from the
/// outside of the square (`folded` 0) to the inside (1).
private struct OpenOutCorners: Shape {
  var folded: CGFloat
  var animatableData: CGFloat {
    get { folded }
    set { folded = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let arm = rect.width * 0.34
    let reach = arm * folded
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
    path.addLine(to: CGPoint(x: rect.minX + reach, y: rect.minY + reach))
    path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
    path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
    path.addLine(to: CGPoint(x: rect.maxX - reach, y: rect.maxY - reach))
    path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
    return path
  }
}

/// A panel Loci keeps. When Loci rewrites it, the new rows fade in over the old; the items in it change in
/// place, and the person's edits show at once.
struct PanelCard: View {
  let panel: Panel
  var refreshing = false
  let actions: PanelActions
  /// The person's take on the lines of its lists.
  var marks: [PanelLineKey: PanelLineMark] = [:]
  var open = false
  var page = 0
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.undoManager) private var undoManager
  @Environment(\.controlActiveState) private var activeState
  @Environment(\.panelItemIDs) private var itemIDs
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var editor: PanelEditor
  @State private var carry = ItemCarry()

  /// `arrived` starts Loci's items ringed as if they just came in, for a snapshot.
  init(
    panel: Panel, refreshing: Bool = false, actions: PanelActions, marks: [PanelLineKey: PanelLineMark] = [:],
    open: Bool = false, page: Int = 0, arrived: Set<String> = []
  ) {
    self.panel = panel
    self.refreshing = refreshing
    self.actions = actions
    self.marks = marks
    self.open = open
    self.page = page
    _editor = State(initialValue: PanelEditor(arrived: arrived))
  }

  var body: some View {
    let shown = editor.shown(panel)
    let face = panel.face
    PanelFrame(
      title: Text(verbatim: panel.title), menu: PanelMenu.entries(for: .panel(panel)), open: open, choose: choose
    ) {
      if let progress = CheckProgress(shown) {
        CheckRing(progress: progress)
        if !panel.sources.isEmpty { SiteBadges(sites: panel.sources) }
      } else {
        SiteBadges(sites: panel.sources)
      }
    } content: {
      ZStack(alignment: .topLeading) {
        rows(of: shown).id(face).transition(.opacity)
        CarriedItem(carry: carry)
      }
      .opacity(refreshing ? 0.5 : 1)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: face)
      .animation(reduceMotion ? nil : Motion.quick, value: refreshing)
    }
    .environment(\.panelEditing, changesAllowed ? editing(shown) : nil)
    .environment(\.itemCarry, carry)
    .task(id: carry.carried != nil) {
      guard carry.carried != nil else { return }
      let escape = EscapeKey { carry.callOff() }
      defer { escape.stop() }
      while carry.carried != nil, !Task.isCancelled {
        carry.listen(
          escape: CGEventSource.keyState(.combinedSessionState, key: Board.escape),
          buttonDown: CGEventSource.buttonState(.combinedSessionState, button: .left))
        try? await Task.sleep(for: Board.listening)
      }
    }
    .onChange(of: activeState) { if activeState == .inactive { carry.callOff() } }
    .onChange(of: panel, initial: true) { editor.settle(on: panel) }
  }

  @ViewBuilder private func rows(of shown: Panel) -> some View {
    switch shown.body {
    case .rows(let rows): PanelRows(rows: rows, actions: actions)
    case .pages(let pages): PanelPager(pages: pages, actions: actions, page: page)
    }
  }

  /// What the rows may do; nothing while the Mac behind the window cannot take changes.
  private func editing(_ shown: Panel) -> PanelEditing {
    let name = panel.name
    let actions = actions
    return PanelEditing(
      panel: shown,
      make: { edit in
        editor.make(edit, send: { await actions.edit(EditPanel(name, $0)) }, undoManager: undoManager)
      },
      mark: { line, mark in
        editor.mark(
          line, mark, was: marks[line] ?? PanelLineMark(),
          send: { await actions.mark(MarkPanelLine(name, $0, $1)) }, undoManager: undoManager)
      },
      newID: itemIDs.make, arrived: editor.arrived, marks: marks)
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

extension Panel {
  /// What the panel shows apart from its items, so the panel fades to new rows when Loci rewrites it but not
  /// when an item changes.
  fileprivate var face: PanelBody {
    ((try? changingSections { section throws(PanelProblems) in section.items = [] }) ?? self).body
  }
}

/// Makes the id of an item the person adds to a panel.
struct PanelItemIDs: Sendable {
  let make: @Sendable () -> String

  static let random = PanelItemIDs { EntityID().description }
}

extension EnvironmentValues {
  @Entry var panelItemIDs = PanelItemIDs.random
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
