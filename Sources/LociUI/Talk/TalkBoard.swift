import AppKit
import LociModel
import SwiftUI

/// Names the main page's own coordinates, which its lanes and panels report their frames in.
enum Board {
  static let space = "talkBoard"
  /// Escape calls a drag off, a panel's or an item's; `callsOffOnEscape` asks the keyboard this often while one
  /// lasts.
  static let escape: CGKeyCode = 53
  static let listening = Duration.milliseconds(20)
}

/// The main page's lanes: the conversation and the panel lanes around it, kept together in the middle of the
/// page. A panel moves by dragging it, the conversation by the grip above it, and a lane's width by the gap
/// beside it or the row's outer edge. What is dragged shows in place at once; the layout is kept when the drag
/// ends.
struct TalkBoard<Conversation: View>: View {
  @Binding var layout: TalkLayout
  /// The panels, once the host has them; without them the conversation has the page to itself.
  let column: PanelColumn?
  let showsPanels: Bool
  var building: PanelSources?
  var making = false
  /// How far the panel lanes rise over the top of the board, into room the conversation keeps for its grip.
  var panelRise: CGFloat = 0
  let actions: PanelActions
  @ViewBuilder var conversation: Conversation
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var reports = BoardFrameReports()
  @State private var pointer = BoardPointer()
  @State private var preview: TalkLayout?
  @State private var carried: Carried?
  @State private var conversationDrag: ConversationDrag?
  @State private var widthDrag: TalkLayout.WidthDrag?
  @State private var pointedAtConversation = false
  @State private var openRail: String?
  /// Where the drag going on started, and where the one called off by Esc or by the window losing the keyboard
  /// started; the rest of that drag is ignored.
  @State private var dragStart: CGPoint?
  @State private var calledOff: CGPoint?
  @Environment(\.controlActiveState) private var activeState
  @Environment(\.panelHome) private var panelHome

  /// A panel being dragged: where it was grabbed, how large it is, the layout the drag started from, and the
  /// new lane it would open.
  struct Carried {
    let key: String
    let grab: CGSize
    let size: CGSize
    let start: TalkLayout
    var newLane: TalkLayout.Side?
  }

  /// Where the conversation stood when it was picked up.
  struct ConversationDrag {
    let start: CGFloat
  }

  private var frames: BoardFrames { reports.frames }

  var body: some View {
    GeometryReader { page in
      let shown = shownLayout
      let fit = shown.fit(in: page.size.width)
      HStack(spacing: 0) {
        ForEach(Array(shown.lanes.enumerated()), id: \.element.id) { index, lane in
          if index > 0 {
            gap(between: shown.lanes[index - 1], and: lane, fit: fit)
          }
          view(of: lane, in: shown, fit: fit, height: page.size.height)
        }
      }
      .overlay(alignment: .leading) { edge(.leading, of: shown, fit: fit) }
      .overlay(alignment: .trailing) { edge(.trailing, of: shown, fit: fit) }
      .padding(.leading, fit.inset)
      .frame(width: page.size.width, height: page.size.height, alignment: .leading)
      .overlay(alignment: .topLeading) { dropLine(over: shown, height: page.size.height) }
      .overlay(alignment: .topLeading) { ghost }
      .animation(reduceMotion || widthDrag != nil ? nil : Motion.standard, value: fit)
    }
    .coordinateSpace(.named(Board.space))
    .environment(\.boardFrames, reports)
    .environment(\.panelLineMarks, column?.marks ?? [:])
    .environment(\.panelData, PanelData(readings: column?.readings ?? PanelReadings(), home: panelHome))
    .callsOffOnEscape(while: dragging) { callOff() }
    .onChange(of: activeState) {
      if activeState == .inactive { callOff() }
    }
  }

  private var dragging: Bool { carried != nil || conversationDrag != nil || widthDrag != nil }

  /// Whether the drag that started at `start` still counts; a new drag clears what an earlier one called off.
  private func heard(_ start: CGPoint) -> Bool {
    if let calledOff {
      guard calledOff != start else { return false }
      self.calledOff = nil
    }
    if dragStart != start { dragStart = start }
    return true
  }

  /// Whether the drag that started at `start` was called off, by Escape or by leaving the window; its end is then
  /// ignored once.
  private func endsCalledOff(_ start: CGPoint) -> Bool {
    guard calledOff == start else { return false }
    calledOff = nil
    return true
  }

  /// Puts everything back as it was before the drag.
  private func callOff() {
    guard dragging else { return }
    calledOff = dragStart
    withAnimation(reduceMotion ? nil : Motion.standard) {
      preview = nil
      carried = nil
      conversationDrag = nil
      pointer.conversationShift = 0
      widthDrag = nil
    }
  }

  private var keys: [String] { column?.slots.map(\.key) ?? [] }
  private var slots: [String: PanelSlot] {
    Dictionary(column?.slots.map { ($0.key, $0) } ?? [], uniquingKeysWith: { first, _ in first })
  }

  /// The layout as it is drawn: the one being dragged into shape, or the kept one holding today's panels. With
  /// panels hidden, or none yet, the conversation stands alone; with no panels at all, one empty lane offers to
  /// make the first.
  private var shownLayout: TalkLayout {
    let held = widthDrag?.preview ?? preview ?? layout.holding(keys)
    guard showsPanels, column != nil else {
      return TalkLayout(leading: [], conversationWidth: held.conversationWidth, trailing: [])
    }
    guard held.panelLanes.isEmpty else { return held }
    return TalkLayout(
      leading: [], conversationWidth: held.conversationWidth,
      trailing: [PanelLane(id: "right", width: TalkLayout.standard.trailing[0].width, keys: [])])
  }

  /// The lane that holds the new-panel button: the nearest on the right, else the nearest on the left.
  private func foot(in layout: TalkLayout) -> String? {
    (layout.trailing.first ?? layout.leading.last)?.id
  }

  @ViewBuilder private func view(of lane: TalkLayout.Lane, in shown: TalkLayout, fit: TalkLayout.Fit, height: CGFloat)
    -> some View
  {
    switch lane {
    case .conversation:
      conversationLane(width: fit.width(of: lane))
    case .panels(let panels):
      if fit.folds(lane) {
        RailLane(
          lane: panels, slots: panels.keys.compactMap { slots[$0] }, refreshing: column?.refreshing ?? [],
          actions: actions, side: shown.leading.contains(panels) ? .leading : .trailing,
          deck: panels.id == foot(in: shown),
          open: Binding(get: { openRail == panels.id }, set: { openRail = $0 ? panels.id : nil })
        )
        .frame(height: height + panelRise)
        .offset(y: -panelRise)
      } else {
        PanelLaneView(
          slots: panels.keys.compactMap { slots[$0] }, refreshing: column?.refreshing ?? [],
          foot: panels.id == foot(in: shown), building: building, making: making, actions: actions,
          hollow: carried.map { ($0.key, $0.size.height) }
        )
        .frame(width: fit.width(of: lane), height: height + panelRise)
        .boardFrame(lane: panels.id)
        .gesture(carry(in: panels))
        .offset(y: -panelRise)
      }
    }
  }

  private func conversationLane(width: CGFloat) -> some View {
    let lifted = conversationDrag != nil
    let shape = RoundedRectangle(cornerRadius: Radius.lane, style: .continuous)
    return Color.clear
      .frame(width: width)
      .boardFrame(lane: TalkLayout.Lane.conversation.id)
      .overlay {
        conversation
          .environment(\.messageWidest, TalkScale.widest(in: width))
          .background {
            shape.fill(Palette.canvas)
              .shadow(color: Palette.liftShadow, radius: lifted ? 30 : 0, y: lifted ? 18 : 0)
              .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline).opacity(lifted ? 1 : 0))
          }
          .scaleEffect(lifted ? 0.985 : 1)
          .shiftedWithConversation(pointer)
          .overlay(alignment: .top) {
            ConversationGrip(lifted: lifted)
              .shiftedWithConversation(pointer, y: -Size.gripLift)
              .opacity(pointedAtConversation || lifted ? 1 : 0)
              .gesture(moveConversation)
          }
      }
      .onHover { pointed in
        withAnimation(reduceMotion ? nil : Motion.quick) { pointedAtConversation = pointed }
      }
      .zIndex(lifted ? 1 : 0)
  }

  private var moveConversation: some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named(Board.space))
      .onChanged { value in
        guard heard(value.startLocation), let frame = frames.lanes[TalkLayout.Lane.conversation.id] else { return }
        if conversationDrag == nil {
          conversationDrag = ConversationDrag(start: frame.minX)
          pointer.conversationShift = 0
          preview = shownLayout
        }
        guard let drag = conversationDrag, let shown = preview else { return }
        let shift = value.translation.width - (frame.minX - drag.start)
        pointer.conversationShift = shift
        let place = shown.conversationPlace(over: frame.offsetBy(dx: shift, dy: 0), frames: frames)
        if place != shown.conversationPlace {
          withAnimation(reduceMotion ? nil : Motion.standard) { preview = shown.movingConversation(to: place) }
        }
      }
      .onEnded { value in
        guard !endsCalledOff(value.startLocation) else { return }
        withAnimation(reduceMotion ? nil : Motion.standard) {
          if let preview { layout = preview }
          preview = nil
          conversationDrag = nil
          pointer.conversationShift = 0
        }
      }
  }

  private func carry(in lane: PanelLane) -> some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .named(Board.space))
      .onChanged { value in
        guard heard(value.startLocation) else { return }
        if carried == nil {
          guard
            let key = lane.keys.first(where: { frames.panels[$0]?.contains(value.startLocation) == true }),
            let frame = frames.panels[key]
          else { return }
          let start = shownLayout
          pointer.location = value.location
          carried = Carried(
            key: key,
            grab: CGSize(width: value.startLocation.x - frame.minX, height: value.startLocation.y - frame.minY),
            size: frame.size, start: start)
          preview = start
        }
        guard let moving = carried, let shown = preview else { return }
        pointer.location = value.location
        let drop = shown.drop(of: moving.key, at: value.location, frames: frames, folded: [])
        let newLane: TalkLayout.Side? = if case .newLane(let side) = drop { side } else { nil }
        if newLane != moving.newLane { carried?.newLane = newLane }
        guard let drop, case .lane(let id, _) = drop, moving.start.panelLanes.contains(where: { $0.id == id }) else {
          return
        }
        let next = moving.start.moving(moving.key, to: drop, keepingEmpty: true)
        if next != shown { withAnimation(reduceMotion ? nil : Motion.standard) { preview = next } }
      }
      .onEnded { value in
        guard !endsCalledOff(value.startLocation) else { return }
        withAnimation(reduceMotion ? nil : Motion.standard) {
          if let moving = carried, let side = moving.newLane {
            layout = moving.start.moving(moving.key, to: .newLane(side))
          } else if let preview {
            layout = preview.withoutEmptyLanes()
          }
          preview = nil
          carried = nil
        }
      }
  }

  /// The panel being dragged, lifted and tilted under the pointer.
  @ViewBuilder private var ghost: some View {
    if let carried, let slot = slots[carried.key] {
      PanelSlotView(slot: slot, refreshing: column?.refreshing ?? [], actions: actions)
        .frame(width: carried.size.width)
        .rotationEffect(.degrees(reduceMotion ? 0 : 1.2))
        .scaleEffect(reduceMotion ? 1 : 1.02)
        .shadow(color: Palette.liftShadow, radius: 28, y: 18)
        .underPointer(pointer, grab: carried.grab)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
  }

  /// Where a new lane would open, while a panel is held past the conversation at the end of the row.
  @ViewBuilder private func dropLine(over shown: TalkLayout, height: CGFloat) -> some View {
    let row = shown.lanes.compactMap { frames.lanes[$0.id] }.reduce(CGRect.null) { $0.union($1) }
    if let side = carried?.newLane, !row.isNull {
      Capsule()
        .fill(Palette.accent)
        .frame(width: 4, height: max(height - Spacing.l, 0))
        .shadow(color: Palette.accent.opacity(0.5), radius: 10)
        .offset(x: side == .leading ? row.minX - Spacing.m : row.maxX + Spacing.s, y: Spacing.s)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .allowsHitTesting(false)
    }
  }

  private func gap(between left: TalkLayout.Lane, and right: TalkLayout.Lane, fit: TalkLayout.Fit) -> some View {
    let folded = fit.folds(left) || fit.folds(right)
    return LaneGap(enabled: !folded) { distance, start in
      resize(.gap(left, right), fit: fit, by: distance, from: start)
    } ended: { distance, start in
      settleWidths(at: distance, from: start)
    }
  }

  @ViewBuilder private func edge(_ side: TalkLayout.Side, of shown: TalkLayout, fit: TalkLayout.Fit) -> some View {
    let lanes = shown.lanes
    if let lane = side == .leading ? lanes.first : lanes.last, !fit.folds(lane) {
      LaneGap(enabled: true, outer: true) { distance, start in
        resize(.edge(side, lane), fit: fit, by: distance, from: start)
      } ended: { distance, start in
        settleWidths(at: distance, from: start)
      }
      .offset(x: side == .leading ? -TalkLayout.gutter : TalkLayout.gutter)
    }
  }

  private func resize(
    _ handle: TalkLayout.WidthDrag.Handle, fit: TalkLayout.Fit, by distance: CGFloat, from start: CGPoint
  ) {
    guard heard(start) else { return }
    var drag = widthDrag ?? TalkLayout.WidthDrag(handle, layout: layout.holding(keys), fit: fit)
    drag.move(by: distance)
    if widthDrag?.preview != drag.preview { widthDrag = drag }
  }

  private func settleWidths(at distance: CGFloat, from start: CGPoint) {
    guard !endsCalledOff(start), var drag = widthDrag else { return }
    drag.move(by: distance)
    layout = drag.preview
    widthDrag = nil
  }
}
