import LociModel
import SwiftUI

/// How sections of items start, for a snapshot: words typed into a section's empty row, an empty row the
/// pointer is on, and sections whose done items are opened out.
struct PanelItemsLook {
  var typed: [String: String] = [:]
  var pointed: Set<String> = []
  var opened: Set<String> = []
}

extension EnvironmentValues {
  @Entry var panelItemsLook = PanelItemsLook()
}

extension SectionRows.Row {
  /// Keeps each item's row, and its drag, as the hollow moves around it and as it is carried.
  fileprivate var id: String { item?.id ?? "/hollow" }

  fileprivate var item: PanelItem? {
    switch self {
    case .item(let item), .carried(let item): item
    case .hollow: nil
    }
  }
}

/// One section of items: its name, the items still to do with the pinned ones first, an empty row to add
/// to it, and the done items folded into dots at that row's end.
struct PanelItemsView: View {
  let section: PanelItems
  @Environment(\.panelEditing) private var editing
  @Environment(\.itemCarry) private var carry
  @Environment(\.panelItemsLook) private var look
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var lingering: Set<String> = []
  @State private var opened: Bool?
  /// How long a ticked item stays in place, struck through, before it sinks into the dots.
  static let linger = Duration.milliseconds(560)
  /// A section without a name starts higher by its first row's inset, so its first item's words sit where a
  /// name would: the same distance under the panel's title either way.
  static let unnamedTop = Spacing.xxs - PanelItemRow.inset

  var body: some View {
    let shape = SectionShape(section, lingering: lingering)
    let target = carry?.carried?.target.flatMap { $0.section == section.id ? $0 : nil }
    let rows = SectionRows(shape, carrying: carry?.carried?.item.id, hollow: target?.index)
    VStack(alignment: .leading, spacing: 0) {
      if let name = section.name {
        Text(verbatim: name).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkMuted)
          .padding(.horizontal, Spacing.xs).padding(.bottom, Spacing.xxs)
      }
      ForEach(rows.rows, id: \.id) { row in
        if let item = row.item {
          let carried = row == .carried(item)
          self.row(item)
            .frame(height: carried ? 0 : nil, alignment: .top)
            .opacity(carried ? 0 : 1)
            .accessibilityHidden(carried)
            .panelRow()
            .onGeometryChange(for: CGRect.self) {
              $0.frame(in: .named(PanelRowEdges.space))
            } action: { frame in
              if !carried { carry?.report(row: item.id, in: section.id, at: frame) }
            }
        } else {
          hollow
        }
      }
      if (section.adds && editing != nil) || !shape.done.isEmpty {
        NewItemSlot(
          adds: section.adds && editing != nil, done: shape.done.count,
          opened: Binding(get: { isOpen }, set: { opened = $0 }),
          typed: look.typed[section.id] ?? "", pointed: look.pointed.contains(section.id)
        ) { text in
          guard let editing else { return }
          editing.make(.put(.yours(id: editing.newID(), text: text), section: section.id, at: nil))
        }
        .panelRow()
      }
      if isOpen {
        ForEach(shape.done) { item in
          row(item).panelRow()
            .transition(reduceMotion ? .identity : .offset(y: -8).combined(with: .opacity))
        }
      }
    }
    .padding(.top, section.name == nil ? Self.unnamedTop : Spacing.xxs)
    .padding(.bottom, Spacing.s)
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .named(PanelRowEdges.space))
    } action: { frame in
      carry?.report(section: section.id, at: frame)
    }
    .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.42), value: rows)
    .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.35), value: isOpen)
  }

  private var isOpen: Bool { opened ?? look.opened.contains(section.id) }

  private var hollow: some View {
    ItemHollow(height: carry?.carried?.size.height ?? 36)
  }

  @ViewBuilder private func row(_ item: PanelItem) -> some View {
    let actions = editing.map { editing in
      ItemRowActions(
        tick: { tick(item, editing: editing) },
        replace: { changed in editing.make(.put(changed, section: section.id, at: index(of: item))) },
        remove: { editing.make(.remove(item.id)) })
    }
    let dragging = carry.flatMap { carry in
      editing == nil || item.done
        ? nil
        : ItemDragging(
          moved: { value in carry.move(item, checks: section.checks, from: value.startLocation, to: value.location) },
          ended: { drop(carry.end()) })
    }
    PanelItemRow(
      item: item, checks: section.checks, actions: actions, arrived: editing?.arrived.contains(item.id) == true,
      dragging: dragging)
  }

  private func index(of item: PanelItem) -> Int? {
    section.items.firstIndex { $0.id == item.id }
  }

  private func tick(_ item: PanelItem, editing: PanelEditing) {
    if item.proposed {
      editing.make(.put(item.taken, section: section.id, at: index(of: item)))
      return
    }
    var changed = item
    changed.done.toggle()
    if changed.done, !reduceMotion {
      lingering.insert(item.id)
      Task {
        try? await Task.sleep(for: Self.linger)
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) { _ = lingering.remove(item.id) }
      }
    }
    editing.make(.put(changed, section: section.id, at: index(of: item)))
  }

  private func drop(_ landing: ItemCarry.Landing?) {
    guard let landing, let editing,
      let into = editing.panel.sections.first(where: { $0.id == landing.target.section })
    else { return }
    let edit = ItemDrop.edit(landing.item, into: into, at: landing.target.index)
    if (try? editing.panel.applying(edit)) != editing.panel { editing.make(edit) }
  }
}

/// The empty row at a section's foot: a dashed circle that turns solid and shows a plus under the pointer.
/// Clicking it puts the cursor in the row; Return adds the item and leaves a new empty row ready, Escape
/// clears it. At its end, the section's done items as dots.
struct NewItemSlot: View {
  let adds: Bool
  let done: Int
  @Binding var opened: Bool
  let add: (String) -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var text: String
  @State private var pointed: Bool
  @FocusState private var focused: Bool

  init(
    adds: Bool, done: Int, opened: Binding<Bool>, typed: String = "", pointed: Bool = false,
    add: @escaping (String) -> Void
  ) {
    self.adds = adds
    self.done = done
    _opened = opened
    self.add = add
    _text = State(initialValue: typed)
    _pointed = State(initialValue: pointed)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if adds {
        AddRing(pointed: pointed, typing: focused || !text.isEmpty).padding(.top, 2)
        TextField("", text: $text, axis: .vertical)
          .textFieldStyle(.plain)
          .font(.system(size: 14.5))
          .foregroundStyle(Palette.ink)
          .focused($focused)
          .onSubmit(commit)
          .onExitCommand {
            text = ""
            focused = false
          }
          .accessibilityLabel(Text(.loci("panels.addItem")))
      } else {
        Spacer(minLength: 0)
      }
      if done > 0 {
        DoneDots(count: done, opened: opened || pointed)
          .onTapGesture { opened.toggle() }
          .accessibilityAddTraits(.isButton)
          .accessibilityLabel(Text(.loci("panels.doneItems \(done)")))
      }
    }
    .padding(.vertical, 7)
    .padding(.horizontal, Spacing.xs)
    .frame(minHeight: 36)
    .contentShape(Rectangle())
    .onTapGesture { if adds { focused = true } }
    .onHover { hovering in withAnimation(reduceMotion ? nil : Motion.quick) { pointed = hovering } }
    .pointerStyle(adds ? .horizontalText : nil)
  }

  private func commit() {
    let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
    text = ""
    guard !words.isEmpty else { return }
    add(words)
    focused = true
  }
}

/// The circle of the empty row: dashed, solid with a plus under the pointer, and tucked in while typing.
private struct AddRing: View {
  let pointed: Bool
  let typing: Bool
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    let solid = pointed || typing
    ZStack {
      Circle().strokeBorder(
        typing ? Palette.inkMuted : solid ? Palette.inkFaint : Palette.lineStrong,
        style: StrokeStyle(lineWidth: 1.5, dash: solid ? [] : [2.6, 2.2]))
      Image(systemName: Symbols.add).font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.inkMuted)
        .opacity(pointed && !typing ? 1 : 0)
        .rotationEffect(.degrees(pointed && !typing ? 0 : typing ? 90 : -90))
        .scaleEffect(pointed && !typing ? 1 : 0.3)
    }
    .frame(width: 18, height: 18)
    .scaleEffect(typing ? 0.92 : 1)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35), value: pointed)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35), value: typing)
  }
}

/// Done items as small ticked dots, overlapping; they spread apart under the pointer or while opened out.
private struct DoneDots: View {
  static let most = 6
  let count: Int
  let opened: Bool
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: opened ? 3 : -4) {
      ForEach(0..<min(count, Self.most), id: \.self) { _ in
        Image(systemName: Symbols.done).font(.system(size: 6.5, weight: .heavy)).foregroundStyle(Palette.surface)
          .frame(width: 14, height: 14)
          .background(Palette.ink.opacity(opened ? 0.5 : 0.26), in: .circle)
          .background(Circle().fill(Palette.surface).padding(-2))
      }
    }
    .frame(height: 22)
    .padding(.leading, Spacing.xs)
    .contentShape(Rectangle())
    .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: opened)
  }
}

/// How far along the panel's first section that can be ticked is; once all is done it turns amber and
/// swells once.
struct CheckRing: View {
  let progress: CheckProgress
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle().stroke(Palette.lineStrong, lineWidth: 2.4)
      Circle().trim(from: 0, to: progress.fraction)
        .stroke(progress.isFull ? Palette.accent : Palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(3)
    .frame(width: Size.siteMark, height: Size.siteMark)
    .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.7), value: progress)
    .phaseAnimator([false, true], trigger: progress.isFull) { ring, swelling in
      ring.scaleEffect(swelling && progress.isFull && !reduceMotion ? 1.18 : 1)
        .shadow(color: Palette.accent.opacity(swelling && progress.isFull && !reduceMotion ? 0.8 : 0), radius: 6)
    } animation: { _ in
      .easeOut(duration: 0.4)
    }
    .accessibilityLabel(Text(.loci("panels.progress \(progress.done) \(progress.all)")))
  }
}
