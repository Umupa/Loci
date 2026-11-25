import AppKit
import LociModel
import SwiftUI

/// A panel's frame keeps whole rows readable and previews the overflow until the panel is opened out.
struct PanelFrame<Marks: View, Content: View>: View {
  let title: Text
  /// When the numbers in it were got, for a panel whose rows point at sources.
  var time: PanelDataTime?
  let menu: [PanelMenu]
  let choose: (PanelMenu) -> Void
  @ViewBuilder var marks: Marks
  @ViewBuilder var content: Content
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var open: Bool
  @State private var height: CGFloat = 0
  @State private var rows: [ClosedRange<CGFloat>] = []

  /// `open` starts the panel opened out, for a snapshot.
  init(
    title: Text, time: PanelDataTime? = nil, menu: [PanelMenu], open: Bool = false,
    choose: @escaping (PanelMenu) -> Void, @ViewBuilder marks: () -> Marks, @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.time = time
    self.menu = menu
    self.choose = choose
    self.marks = marks()
    self.content = content()
    _open = State(initialValue: open)
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    let overflow = PanelPreview(height: height, rows: rows)
    let preview = open ? nil : overflow
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.bottom, 14)
      content
        .environment(\.panelPreview, preview)
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(.named(PanelRowBounds.space))
        .onPreferenceChange(PanelRowBounds.self) { rows = $0 }
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          height = $0
        }
        .frame(height: preview?.height, alignment: .top)
        .clipShape(Rectangle().inset(by: preview == nil ? -Spacing.s : 0))
        .mask(alignment: .bottom) { PanelFade(height: preview?.fadeHeight) }
        .overlay(alignment: .bottom) {
          if let preview {
            Color.clear
              .frame(height: preview.fadeHeight)
              .contentShape(Rectangle())
              .onTapGesture(perform: toggle)
          }
        }
      if overflow != nil {
        OpenOutButton(open: open, action: toggle)
          .frame(maxWidth: .infinity)
          .padding(.top, open ? Spacing.xs : Spacing.xxs)
          .padding(.bottom, Spacing.s - Spacing.xxs)
          .transition(.opacity)
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
      if let time { PanelTimeMark(time: time) }
    }
    .frame(height: Size.siteMark)
  }

  private func toggle() {
    withAnimation(reduceMotion ? nil : Motion.standard) { open.toggle() }
  }
}

/// Lets the content show in full, or, over the preview strip of a cut panel, fade out into the panel.
private struct PanelFade: View {
  let height: CGFloat?

  var body: some View {
    if let height {
      VStack(spacing: 0) {
        Rectangle()
        LinearGradient(
          stops: [.init(color: .black.opacity(0.7), location: 0), .init(color: .clear, location: 0.9)],
          startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
      }
    } else {
      Rectangle().padding(-Spacing.s)
    }
  }
}

/// The boundary between readable rows and the strip hinting at more content.
struct PanelPreview: Equatable {
  private static let slack: CGFloat = 40
  private static let rowPreviewHeight = Spacing.l + Spacing.s
  private let clearHeight: CGFloat
  let height: CGFloat
  let fadeHeight: CGFloat

  init?(height: CGFloat, rows: [ClosedRange<CGFloat>]) {
    let rowEnds = rows.map(\.upperBound)
    guard height > Size.panelTallest + Self.slack, let first = rowEnds.min() else { return nil }
    let clearHeight = rowEnds.filter { $0 <= Size.panelTallest }.max() ?? first
    let hidden = rows.filter { $0.upperBound > clearHeight }
    guard let next = hidden.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
    let previewTop = max(clearHeight, next.lowerBound)
    self.clearHeight = clearHeight
    self.height = min(previewTop + Self.rowPreviewHeight, next.upperBound)
    fadeHeight = self.height - previewTop
  }

  func showsRow(endingAt end: CGFloat) -> Bool {
    end <= clearHeight
  }
}

extension EnvironmentValues {
  @Entry fileprivate var panelPreview: PanelPreview?
}

/// Where each row begins and ends, measured from the top of the panel's content.
struct PanelRowBounds: PreferenceKey {
  static let space = "panelRows"
  static let defaultValue: [ClosedRange<CGFloat>] = []

  static func reduce(value: inout [ClosedRange<CGFloat>], nextValue: () -> [ClosedRange<CGFloat>]) {
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
    let peeking = !shown && (bounds?.lowerBound ?? .infinity) < (preview?.height ?? 0)
    content
      .opacity(shown || peeking ? 1 : 0)
      .disabled(!shown)
      .allowsHitTesting(shown)
      .accessibilityHidden(!shown)
      .preference(key: PanelRowBounds.self, value: bounds.map { [$0] } ?? [])
      .onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
        let frame = proxy.frame(in: .named(PanelRowBounds.space))
        return frame.height > 0 ? frame.minY...frame.maxY : nil
      } action: {
        bounds = $0
      }
  }
}

/// The chevron under a cut panel, sitting over its fading preview; it turns over once the panel is open.
private struct OpenOutButton: View {
  let open: Bool
  let action: () -> Void
  @State private var pointed = false

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.unfold)
        .font(.system(size: 10, weight: .semibold))
        .rotationEffect(.degrees(open ? 180 : 0))
        .foregroundStyle(pointed ? Palette.ink : Palette.inkFaint)
        .frame(width: 40, height: 20)
        .background {
          Capsule().fill(Palette.surface).overlay(Capsule().fill(Palette.ink.opacity(pointed ? 0.09 : 0.05)))
        }
        .overlay(Capsule(style: .circular).strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline))
        .contentShape(.capsule)
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .onHover { pointed = $0 }
    .accessibilityLabel(Text(.loci(open ? "panels.close" : "panels.open")))
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
  @Environment(\.panelHome) private var home
  @Environment(\.pinnedPanels) private var pinnedPanels
  @Environment(\.panelData) private var data
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
      title: Text(verbatim: panel.title), time: data.readings.time(of: panel, in: data.home),
      menu: menu, open: open, choose: choose
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
  private var ref: PanelRef { PanelRef(panel.name, in: home) }

  /// A panel the chat's column shows for its project is pinned there.
  private var menu: [PanelMenu] {
    let slot: PanelSlot = if case .project(let id) = home, pinnedHere { .pinned(id, panel) } else { .panel(panel) }
    return PanelMenu.entries(for: slot, in: home, pinned: pinnedPanels.contains(panel.name))
  }

  @Environment(\.pinnedHere) private var pinnedHere

  private func editing(_ shown: Panel) -> PanelEditing {
    let name = ref
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
    case .refresh: actions.refresh(ref)
    case .revise: actions.revise(panel)
    case .pin: actions.pin(ref, true)
    case .unpin: actions.pin(ref, false)
    case .moveToTop:
      if case .project(let id) = home, pinnedHere {
        actions.moveToTop(.pinned(id, panel))
      } else {
        actions.moveToTop(.panel(panel))
      }
    case .remove: actions.remove(ref)
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
