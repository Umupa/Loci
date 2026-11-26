import LociModel
import SwiftUI

/// The gap between two lanes, or at the row's outer edge, that drags their widths. Pointing at it shows a short
/// grip; dragging lengthens it and turns it amber. Beside a folded lane it is only a gap.
struct LaneGap: View {
  let enabled: Bool
  var outer = false
  /// How far it is dragged, and where the drag started.
  let dragged: (CGFloat, CGPoint) -> Void
  let ended: (CGPoint) -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false
  @State private var dragging = false

  var body: some View {
    Color.clear
      .frame(width: TalkLayout.gutter)
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .overlay {
        if enabled {
          Capsule()
            .fill(dragging ? Palette.accent : Palette.lineStrong)
            .frame(width: 4, height: dragging ? 56 : 36)
            .opacity(pointed || dragging ? 1 : 0)
            .scaleEffect(y: pointed || dragging ? 1 : 0.6)
            .animation(reduceMotion ? nil : Motion.standard, value: pointed)
            .animation(reduceMotion ? nil : Motion.standard, value: dragging)
        }
      }
      .pointerStyle(enabled ? .columnResize : nil)
      .onHover { pointed = enabled && $0 }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { value in
            guard enabled else { return }
            dragging = true
            dragged(value.translation.width, value.startLocation)
          }
          .onEnded { value in
            guard enabled else { return }
            dragging = false
            ended(value.startLocation)
          }
      )
      .accessibilityHidden(true)
  }
}

/// The grip above the conversation that moves it among the lanes: two rows of dots in a capsule.
struct ConversationGrip: View {
  let lifted: Bool
  @State private var pointed = false

  var body: some View {
    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
      ForEach(0..<2, id: \.self) { _ in
        GridRow {
          ForEach(0..<4, id: \.self) { _ in
            Circle().frame(width: 2.6, height: 2.6)
          }
        }
      }
    }
    .foregroundStyle(lifted ? Palette.accent : pointed ? Palette.ink : Palette.inkFaint)
    .frame(width: 44, height: 24)
    .background(Palette.fill.opacity(pointed || lifted ? 1 : 0), in: .capsule)
    .contentShape(.capsule)
    .onHover { pointed = $0 }
    .pointerStyle(.grabIdle)
    .help(Text(.loci("talk.moveConversation")))
    .accessibilityLabel(Text(.loci("talk.moveConversation")))
  }
}

/// A lane folded where the window has no room for it: its panels' marks in a short paper capsule at the top of
/// where the lane was, with nothing drawn below; nothing at all for a lane with no panels yet. A mark lifts under the
/// pointer and opens the lane's panels over the page, pointing at it.
struct RailLane: View {
  let lane: PanelLane
  let slots: [PanelSlot]
  var refreshing: Set<String> = []
  let actions: PanelActions
  let side: TalkLayout.Side
  /// Whether this rail holds the deck of next-up cards.
  var deck = false
  @Binding var open: Bool
  @State private var chosen: String?
  @Environment(\.nextUpDeck) private var cards

  private var showsDeck: Bool { deck && !(cards?.cards.isEmpty ?? true) }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      if deck { RailDeck(side: side) }
      ForEach(slots, id: \.key) { slot in
        Button {
          chosen = slot.key
          open = true
        } label: {
          RailMark(slot: slot, refreshing: refreshing.contains(slot.key))
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .help(Text(verbatim: slot.title))
        .accessibilityLabel(Text(verbatim: slot.title))
        .popover(isPresented: shows(slot), arrowEdge: side == .leading ? .trailing : .leading) { sheet }
      }
    }
    .padding(.vertical, Spacing.xs)
    .padding(.horizontal, 7)
    .background {
      if !slots.isEmpty || showsDeck {
        let shape = RoundedRectangle(cornerRadius: Size.railMark / 2 + 7, style: .circular)
        shape.fill(Palette.surface)
          .shadow(color: Palette.liftShadow.opacity(0.3), radius: 10, y: 4)
          .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      }
    }
    .padding(.top, Spacing.s)
    .frame(width: TalkLayout.rail)
    .frame(maxHeight: .infinity, alignment: .top)
    .boardFrame(lane: lane.id)
  }

  /// The lane's panels over the page, pointing at the mark clicked and starting at its panel.
  private var sheet: some View {
    ScrollViewReader { reader in
      ScrollView {
        VStack(spacing: Spacing.s) {
          ForEach(slots, id: \.key) { slot in
            PanelSlotView(slot: slot, refreshing: refreshing, actions: closing).id(slot.key)
          }
        }
        .padding(Spacing.s)
      }
      .scrollIndicators(.never)
      .frame(width: Size.railSheet)
      .frame(maxHeight: Size.railSheetTallest)
      .onAppear { reader.scrollTo(chosen, anchor: .top) }
    }
  }

  private func shows(_ slot: PanelSlot) -> Binding<Bool> {
    Binding(get: { open && chosen == slot.key }, set: { if !$0 { open = false } })
  }
}

extension RailLane {
  /// What the panels do when opened over the page: whatever opens something else closes them first.
  fileprivate var closing: PanelActions {
    let close = { open = false }
    return PanelActions(
      open: { url in
        close()
        actions.open(url)
      },
      openItem: { item in
        close()
        actions.openItem(item)
      },
      ask: { words in
        close()
        actions.ask(words)
      },
      create: actions.create,
      revise: { panel in
        close()
        actions.revise(panel)
      },
      refresh: actions.refresh, moveToTop: actions.moveToTop, remove: actions.remove, edit: actions.edit,
      mark: actions.mark, pin: actions.pin)
  }
}

/// One panel's mark on a folded lane: its first site, or Loci's face for 「接着读」, breathing while the panel
/// is refreshed.
private struct RailMark: View {
  let slot: PanelSlot
  var refreshing = false
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false

  var body: some View {
    Group {
      switch slot {
      case .reading: LociAvatar(size: Size.railMark)
      case .panel(let panel), .pinned(_, let panel):
        SiteBadges(sites: Array(panel.sources.prefix(1)), size: Size.railMark, ring: .clear)
      }
    }
    .frame(width: Size.railMark, height: Size.railMark)
    .opacity(refreshing ? 0.55 : 1)
    .scaleEffect(pointed ? 1.12 : 1)
    .shadow(color: Palette.liftShadow.opacity(pointed ? 0.5 : 0), radius: 6, y: 3)
    .animation(reduceMotion ? nil : Motion.quick, value: pointed)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(), value: refreshing)
    .contentShape(.circle)
    .onHover { pointed = $0 }
  }
}

extension PanelSlot {
  /// What the panel is called, as its frame shows.
  var title: String {
    switch self {
    case .reading: String(localized: .loci("panels.reading"))
    case .panel(let panel), .pinned(_, let panel): panel.title
    }
  }
}

extension TalkScale {
  /// The widest a message gets in the main conversation when it is `width` wide.
  static func widest(in width: CGFloat) -> CGFloat {
    TalkLayout.clamp((width - Spacing.xl) * main.share, to: Size.messageWidest...Size.talkMessageWidest)
  }
}

extension EnvironmentValues {
  /// The widest a message in the main conversation gets; the lane it is in sets it.
  @Entry var messageWidest: CGFloat = Size.messageWidest
}
