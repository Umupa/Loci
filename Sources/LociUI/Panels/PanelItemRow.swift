import LociModel
import SwiftUI

/// What an item row asks of its section.
struct ItemRowActions {
  /// Ticks or unticks the item; for Loci's suggestion, takes it.
  let tick: () -> Void
  /// Puts the item back changed, where it is.
  let replace: (PanelItem) -> Void
  let remove: () -> Void
}

/// Dragging an item to another place in its panel.
struct ItemDragging {
  let moved: (DragGesture.Value) -> Void
  let ended: () -> Void
}

/// What the person is typing in an item: nothing, its words, or the note under it.
enum ItemTyping: Equatable {
  case none
  case words(String)
  case note(String)

  /// An item being typed in keeps the pointer for the text: dragging selects words, not the item.
  var takesDrags: Bool { self == .none }
}

/// One item: the circle to tick, its words with the note under them, a pin, and Loci's face on Loci's items.
/// The person rewords their own item by double-clicking it.
struct PanelItemRow: View {
  let item: PanelItem
  let checks: Bool
  /// `nil` while the row only shows, as a dragged copy does.
  var actions: ItemRowActions?
  var arrived = false
  /// `nil` for an item that stays where it is.
  var dragging: ItemDragging?
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false
  @State private var typed = ItemTyping.none
  @FocusState private var typing: Bool
  /// How far the row's words sit inside it, from its top.
  static let inset: CGFloat = 7

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
    HStack(alignment: .top, spacing: 10) {
      if checks || item.proposed { TickCircle(item: item, action: actions?.tick) }
      VStack(alignment: .leading, spacing: 2) {
        words
        aside
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if item.pinned { PinMark().padding(.top, 3) }
      if item.proposed, pointed, let actions {
        SuggestionButtons(take: actions.tick, drop: actions.remove).transition(.opacity)
      }
      if item.by == .loci { LociAvatar(size: 15).opacity(0.85).padding(.top, 3) }
    }
    .padding(.vertical, Self.inset)
    .padding(.horizontal, Spacing.xs)
    .frame(minHeight: 36)
    .background(Palette.ink.opacity(pointed && actions != nil ? 0.075 : 0), in: shape)
    .background(Palette.tint.opacity(arrived ? 1 : 0), in: shape)
    .overlay(shape.strokeBorder(Palette.accentLine.opacity(arrived ? 1 : 0), lineWidth: 1))
    .animation(reduceMotion ? nil : arrived ? nil : .easeOut(duration: 1.2), value: arrived)
    .contentShape(shape)
    .onHover { hovering in withAnimation(reduceMotion ? nil : Motion.quick) { pointed = hovering } }
    .contextMenu { if actions != nil { menu } }
    .highPriorityGesture(drag, including: dragging != nil && typed.takesDrags ? .all : .subviews)
  }

  private var drag: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .named(PanelRowBounds.space))
      .onChanged { dragging?.moved($0) }
      .onEnded { _ in dragging?.ended() }
  }

  @ViewBuilder private var words: some View {
    if case .words(let rewording) = typed {
      TextField("", text: Binding(get: { rewording }, set: { typed = .words($0) }), axis: .vertical)
        .textFieldStyle(.plain)
        .font(.system(size: 14.5))
        .foregroundStyle(Palette.ink)
        .focused($typing)
        .onSubmit { finishRewording(keep: true) }
        .onExitCommand { finishRewording(keep: false) }
        .onChange(of: typing) { if !typing { finishRewording(keep: true) } }
        .onAppear { typing = true }
    } else {
      Text(verbatim: item.text)
        .font(.system(size: 14.5))
        .lineSpacing(2)
        .strikethrough(item.done, color: Palette.inkFaint)
        .foregroundStyle(item.done ? Palette.inkFaint : Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: item.done)
        .onTapGesture(count: 2) {
          if item.by == .you, !item.done, actions != nil { typed = .words(item.text) }
        }
    }
  }

  @ViewBuilder private var aside: some View {
    if case .note(let noting) = typed {
      TextField("", text: Binding(get: { noting }, set: { typed = .note($0) }), axis: .vertical)
        .textFieldStyle(.plain)
        .font(ItemNote.font)
        .foregroundStyle(Palette.inkMuted)
        .focused($typing)
        .onSubmit { finishNoting(keep: true) }
        .onExitCommand { finishNoting(keep: false) }
        .onChange(of: typing) { if !typing { finishNoting(keep: true) } }
        .onAppear { typing = true }
    } else if let words = item.note ?? item.why {
      ItemNote(text: words)
    }
  }

  @ViewBuilder private var menu: some View {
    ForEach(PanelItemMenu.entries(for: item), id: \.self) { entry in
      if entry == .remove { Divider() }
      Button {
        choose(entry)
      } label: {
        Text(entry.name)
      }
    }
  }

  private func choose(_ entry: PanelItemMenu) {
    guard let actions else { return }
    var changed = item
    switch entry {
    case .pin, .unpin:
      changed.pinned.toggle()
      actions.replace(changed)
    case .note, .editNote: typed = .note(item.note ?? "")
    case .take: actions.replace(item.taken)
    case .remove: actions.remove()
    }
  }

  private func finishRewording(keep: Bool) {
    guard case .words(let typed) = typed else { return }
    let words = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    self.typed = .none
    guard keep, !words.isEmpty, words != item.text else { return }
    var changed = item
    changed.text = words
    actions?.replace(changed)
  }

  private func finishNoting(keep: Bool) {
    guard case .note(let typed) = typed else { return }
    let words = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    self.typed = .none
    guard keep, words != (item.note ?? "") else { return }
    var changed = item
    changed.note = words.isEmpty ? nil : words
    actions?.replace(changed)
  }
}

/// The person's note under an item or a line, or Loci's few words on why an item is there: serif, slanted.
struct ItemNote: View {
  static let font = Font.system(size: 13, design: .serif).italic()
  let text: String

  var body: some View {
    Text(verbatim: text).font(Self.font).foregroundStyle(Palette.inkMuted).lineSpacing(1)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// The circle before an item: ticked, it fills with ink and a check draws itself; Loci's suggestion has a
/// dashed one, and clicking it takes the item.
private struct TickCircle: View {
  let item: PanelItem
  let action: (() -> Void)?
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false
  @State private var burst = false

  var body: some View {
    Button {
      if !item.done, !item.proposed, !reduceMotion { burst.toggle() }
      action?()
    } label: {
      ZStack {
        Circle()
          .strokeBorder(
            item.done ? Palette.ink : item.proposed ? Palette.inkMuted : pointed ? Palette.inkMuted : Palette.inkFaint,
            style: StrokeStyle(lineWidth: 1.5, dash: item.proposed ? [2.6, 2.2] : []))
        Circle().fill(Palette.ink).opacity(item.done ? 1 : 0)
        CheckStroke().trim(from: 0, to: item.done ? 1 : 0)
          .stroke(Palette.canvas, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
          .frame(width: 10, height: 10)
        Circle().strokeBorder(Palette.accent, lineWidth: 1.5)
          .phaseAnimator(Burst.allCases, trigger: burst) { ring, phase in
            ring.scaleEffect(phase == .spread ? 1.9 : 0.8).opacity(phase == .start ? 0.9 : 0)
          } animation: { phase in
            phase == .spread ? .easeOut(duration: 0.55) : nil
          }
      }
      .frame(width: 18, height: 18)
      .scaleEffect(pointed ? 1.08 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: item.done)
      .animation(reduceMotion ? nil : Motion.quick, value: pointed)
      .padding(.top, 2)
      .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .disabled(action == nil)
    .onHover { pointed = $0 }
    .accessibilityLabel(Text(.loci(item.proposed ? "panels.take" : item.done ? "panels.untick" : "panels.tick")))
  }
}

/// An amber ring that spreads from the circle once as it is ticked.
private enum Burst: CaseIterable {
  case rest, start, spread
}

/// A check mark drawn in a square.
private struct CheckStroke: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.53))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.8))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.2))
    return path
  }
}

/// The pin on an item or a line the person keeps at the top.
struct PinMark: View {
  var body: some View {
    Image(systemName: Symbols.pin).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent)
      .rotationEffect(.degrees(45))
      .accessibilityLabel(Text(.loci("panels.pinned")))
  }
}

/// ✓ and ×, beside Loci's suggestion while the pointer is on it.
private struct SuggestionButtons: View {
  let take: () -> Void
  let drop: () -> Void

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      button(Symbols.done, label: "panels.take", action: take)
      button(Symbols.cancel, label: "panels.drop", action: drop)
    }
  }

  private func button(_ symbol: String, label: String.LocalizationValue, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.inkMuted)
        .frame(width: 22, height: 22)
        .background(Palette.ink.opacity(0.06), in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .accessibilityLabel(Text(.loci(label)))
  }
}
