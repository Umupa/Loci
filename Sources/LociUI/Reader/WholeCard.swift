import LociModel
import SwiftUI

/// At the top of the highlights: the item's small cover and title, and under them the person's thought on the
/// whole of it, written straight in. Leaving the field or pressing Return saves it; emptying it removes it.
struct WholeCard: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  let item: Item
  let thought: String?
  @State private var draft = ""
  @State private var editing = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 11) {
        Cover(item: item, corner: 4, edge: Size.wholeCover.height)
          .frame(width: Size.wholeCover.width, height: Size.wholeCover.height)
          .shadow(color: .black.opacity(0.18), radius: 3, x: 1, y: 2)
        Text(serif: item.title, Serif.Face(size: 14, weight: .semibold))
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
      }
      if editing || draft.isEmpty {
        field
      } else {
        Text(serif: draft, Serif.Face(size: 15))
          .italic()
          .foregroundStyle(Palette.ink)
          .lineSpacing(3)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        .fill(Palette.surface)
        .overlay(
          RadialGradient(colors: [Palette.tint, .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        )
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(
        focused ? Palette.accent.opacity(0.55) : Palette.line, lineWidth: focused ? 1 : Size.hairline)
    )
    .shadow(color: focused ? Palette.tint : .clear, radius: 4)
    .contentShape(Rectangle())
    .onTapGesture { edit() }
    .animation(Motion.quick, value: focused)
    .onAppear { draft = thought ?? "" }
    .onChange(of: thought) { if !focused { draft = thought ?? "" } }
    .onChange(of: focused) { _, focused in
      guard !focused else { return }
      editing = false
      save()
    }
  }

  private var field: some View {
    TextField(text: $draft, axis: .vertical) {
      Text(.loci("note.wholePrompt"))
    }
    .textFieldStyle(.plain)
    .font(.system(size: 15, design: .serif).italic())
    .foregroundStyle(Palette.ink)
    .lineSpacing(3)
    .lineLimit(1...12)
    .focused($focused)
    .disabled(!changesAllowed)
    .onSubmit { focused = false }
  }

  private func edit() {
    guard changesAllowed else { return }
    editing = true
    focused = true
  }

  private func save() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let wanted = text.isEmpty ? nil : text
    guard wanted != thought else { return }
    Task {
      do throws(HostError) {
        _ = try await host.run(SetWholeThought(item: item.id, thought: wanted))
      } catch {
        draft = thought ?? ""
        showFailure(error)
      }
    }
  }
}
