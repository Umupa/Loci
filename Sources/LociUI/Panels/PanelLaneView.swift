import LociModel
import SwiftUI

/// One lane of panels beside the main conversation, top to bottom on the page itself. The lane nearest
/// the conversation also holds the deck of next-up cards over its panels, and the skeleton of a panel being
/// made and the button that asks for a new one under them. A panel being dragged leaves a hollow where it
/// would land.
struct PanelLaneView: View {
  let slots: [PanelSlot]
  var refreshing: Set<String> = []
  /// Whether this lane holds the skeleton and the button for a new panel.
  var foot = false
  /// What marks the skeleton of a panel being made, while one is.
  var building: PanelSources?
  /// The composer is asking for a new panel, so the button that started it steps back.
  var making = false
  let actions: PanelActions
  /// The panel being dragged, by key, and how tall its hollow is.
  var hollow: (key: String, height: CGFloat)?
  /// Panels that start opened out, and the page a paging panel starts on, by name, for a snapshot.
  var opened: Set<String> = []
  var pages: [String: Int] = [:]
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.nextUpDeck) private var deck
  @State private var position = ScrollPosition(edge: .top)

  var body: some View {
    if slots.isEmpty, building == nil {
      VStack(spacing: Spacing.s) {
        if foot, let deck, !deck.cards.isEmpty { NextUpDeck(state: deck) }
        NewPanelButton(action: actions.create).opacity(making ? 0.35 : 1).disabled(making).changesData()
      }
      .padding(Spacing.s)
      .frame(maxHeight: .infinity, alignment: .top)
    } else {
      lane
    }
  }

  private var lane: some View {
    ScrollView {
      VStack(spacing: Spacing.s) {
        if foot, let deck, !deck.cards.isEmpty { NextUpDeck(state: deck) }
        ForEach(slots, id: \.key) { slot in
          if let hollow, hollow.key == slot.key {
            Hollow(height: hollow.height).boardFrame(panel: slot.key)
          } else {
            PanelSlotView(slot: slot, refreshing: refreshing, actions: actions, opened: opened, pages: pages)
              .boardFrame(panel: slot.key)
              .transition(arrival)
          }
        }
        if foot {
          if let building { PanelSkeleton(sources: building).transition(arrival) }
          NewPanelButton(action: actions.create).opacity(making ? 0.35 : 1).disabled(making || building != nil)
            .changesData()
        }
      }
      .padding(Spacing.s)
      .animation(reduceMotion ? nil : Motion.standard, value: slots.map(\.key))
      .animation(reduceMotion ? nil : Motion.standard, value: building != nil)
      .animation(reduceMotion ? nil : Motion.quick, value: making)
    }
    .scrollPosition($position)
    .scrollIndicators(.never)
    .mask {
      VStack(spacing: 0) {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Spacing.s)
        Color.black
        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Spacing.l)
      }
    }
    .onChange(of: building != nil, initial: true) {
      if building != nil { withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(edge: .bottom) } }
    }
  }

  /// A panel just made rises into place.
  private var arrival: AnyTransition {
    reduceMotion ? .identity : .opacity.combined(with: .offset(y: Spacing.m)).combined(with: .scale(scale: 0.97))
  }
}

/// One panel as a lane draws it: 「接着读」 or one of Loci's.
struct PanelSlotView: View {
  let slot: PanelSlot
  var refreshing: Set<String> = []
  let actions: PanelActions
  var opened: Set<String> = []
  var pages: [String: Int] = [:]
  @Environment(\.panelLineMarks) private var marks
  @Environment(\.projectsByID) private var projectsByID

  var body: some View {
    switch slot {
    case .reading(let readings):
      ReadingPanel(readings: readings, actions: actions)
    case .panel(let panel):
      PanelCard(
        panel: panel, refreshing: refreshing.contains(slot.key), actions: actions, marks: marks[slot.key] ?? [:],
        open: opened.contains(slot.key), page: pages[slot.key] ?? 0)
    case .pinned(let project, let panel):
      PanelCard(
        panel: panel, refreshing: refreshing.contains(slot.key), actions: actions, marks: marks[slot.key] ?? [:],
        open: opened.contains(slot.key), page: pages[slot.key] ?? 0
      )
      .environment(\.panelHome, .project(project))
      .environment(\.pinnedHere, true)
      .environment(\.pinnedProject, projectsByID[project])
      .transformEnvironment(\.panelData) { $0.home = .project(project) }
    }
  }
}

/// Where a dragged panel would land: its size, ringed in amber.
private struct Hollow: View {
  let height: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
    shape.fill(Palette.tint.opacity(0.45))
      .overlay(shape.strokeBorder(Palette.accentLine, lineWidth: 1.5))
      .frame(height: height)
  }
}

extension PanelSlot {
  /// Keeps a slot's place as the page changes: 「接着读」 has one, each panel its name, and a pinned panel its
  /// `PanelRef.key`, as the column keys its marks and refreshes.
  var key: String {
    switch self {
    case .reading: "/reading"
    case .panel(let panel): panel.name
    case .pinned(let project, let panel): PanelRef(panel.name, in: .project(project)).key
    }
  }
}

extension View {
  /// Tells the page where this panel is, so a drag knows where it would land.
  func boardFrame(panel key: String) -> some View {
    modifier(BoardFrameReporter(key: key, lane: false))
  }

  /// Tells the page where this lane is.
  func boardFrame(lane id: String) -> some View {
    modifier(BoardFrameReporter(key: id, lane: true))
  }
}

private struct BoardFrameReporter: ViewModifier {
  let key: String
  let lane: Bool
  @Environment(\.boardFrames) private var frames

  func body(content: Content) -> some View {
    content.onGeometryChange(for: CGRect.self) {
      $0.frame(in: .named(Board.space))
    } action: { frame in
      frames?.frames.place(key, at: frame, lane: lane)
    }
  }
}

extension BoardFrames {
  mutating func place(_ key: String, at frame: CGRect, lane: Bool) {
    if lane { lanes[key] = frame } else { panels[key] = frame }
  }
}

extension EnvironmentValues {
  /// Where the main page keeps the frames its lanes and panels report; elsewhere nothing listens.
  @Entry var boardFrames: BoardFrameReports?
  /// The person's take on the lines of each panel's lists, by panel name, as the column has it.
  @Entry var panelLineMarks: [String: [PanelLineKey: PanelLineMark]] = [:]
}

private struct NewPanelButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: Symbols.add).font(.system(size: 13, weight: .medium))
        Text(.loci("panels.new")).font(.system(size: 14))
      }
      .foregroundStyle(Palette.ink.opacity(0.85))
      .frame(maxWidth: .infinity, minHeight: Size.composerHeight)
      .background(Palette.surface, in: .capsule)
      .overlay(Capsule(style: .circular).strokeBorder(Palette.bubbleEdge, lineWidth: Size.hairline))
      .contentShape(.capsule)
    }
    .buttonStyle(PressStyle(scale: 0.98))
  }
}
