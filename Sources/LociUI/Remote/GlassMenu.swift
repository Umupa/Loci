import SwiftUI

/// One line of a `GlassMenu`.
enum GlassMenuEntry<ID: Hashable> {
  case item(GlassMenuItem<ID>)
  case separator
}

struct GlassMenuItem<ID: Hashable> {
  let id: ID
  let title: Text
  var symbol: String?
  var checked = false
  var enabled = true
}

/// A menu Loci draws itself on the system's glass, so it can sit inside the window at the width the design
/// gives it. The arrow keys move through the items that can be chosen, Return chooses, Escape closes.
struct GlassMenu<ID: Hashable>: View {
  let entries: [GlassMenuEntry<ID>]
  let choose: (ID) -> Void
  let close: () -> Void
  @State private var highlighted: ID?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
        switch entry {
        case .item(let item): row(item)
        case .separator:
          Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(
            .vertical, 5
          ).padding(.horizontal, Spacing.xs)
        }
      }
    }
    .padding(5)
    .solidGlass(in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    .shadow(color: .black.opacity(0.24), radius: 25, y: 18)
    .focusable()
    .focusEffectDisabled()
    .focused($focused)
    .onAppear { focused = true }
    .onKeyPress(.downArrow) { move(by: 1) }
    .onKeyPress(.upArrow) { move(by: -1) }
    .onKeyPress(.return) {
      guard let highlighted else { return .ignored }
      choose(highlighted)
      return .handled
    }
    .onKeyPress(.escape) {
      close()
      return .handled
    }
  }

  private func row(_ item: GlassMenuItem<ID>) -> some View {
    let lit = item.enabled && highlighted == item.id
    return Button {
      choose(item.id)
    } label: {
      HStack(spacing: 7) {
        Image(systemName: Symbols.done)
          .font(.system(size: 9, weight: .semibold))
          .opacity(item.checked ? 1 : 0)
          .frame(width: 12)
        if let symbol = item.symbol {
          Image(systemName: symbol)
            .font(.system(size: 13))
            .foregroundStyle(lit ? Palette.onAccent : item.enabled ? Palette.inkMuted : Palette.inkFaint)
            .frame(width: 16)
        }
        item.title.lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(Typography.body)
      .foregroundStyle(lit ? Palette.onAccent : item.enabled ? Palette.ink : Palette.inkFaint)
      .padding(.leading, 6)
      .padding(.trailing, Spacing.xs)
      .frame(height: 26)
      .background(RoundedRectangle(cornerRadius: Radius.thumbnail).fill(lit ? Palette.accent : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!item.enabled)
    .onHover { inside in
      if inside { highlighted = item.id } else if highlighted == item.id { highlighted = nil }
    }
    .accessibilityAddTraits(item.checked ? .isSelected : [])
  }

  private var choosable: [ID] {
    entries.compactMap {
      if case .item(let item) = $0, item.enabled { return item.id }
      return nil
    }
  }

  private func move(by step: Int) -> KeyPress.Result {
    let ids = choosable
    guard !ids.isEmpty else { return .ignored }
    let index = highlighted.flatMap { ids.firstIndex(of: $0) }
    let next = index.map { ($0 + step + ids.count) % ids.count } ?? (step > 0 ? 0 : ids.count - 1)
    highlighted = ids[next]
    return .handled
  }
}

extension View {
  /// Shows `menu` over the window while `isPresented`; a click anywhere outside it closes it, and does nothing
  /// else, as a system menu does.
  func glassMenuLayer(isPresented: Binding<Bool>, @ViewBuilder menu: () -> some View) -> some View {
    overlay {
      if isPresented.wrappedValue {
        ZStack(alignment: .bottomLeading) {
          Color.clear.contentShape(Rectangle()).onTapGesture { isPresented.wrappedValue = false }
          menu()
        }
        .transition(.opacity.combined(with: .offset(y: 6)))
      }
    }
  }
}
