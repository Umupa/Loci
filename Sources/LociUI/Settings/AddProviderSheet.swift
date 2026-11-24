import LociModel
import SwiftUI

/// The providers that can be added, found by name: the presets, greyed out once added, and one of your own.
struct AddProviderSheet: View {
  let added: Set<ModelPreset>
  let choose: (ModelPreset) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @FocusState private var searching: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 9) {
        Image(systemName: Symbols.search).font(.system(size: 14)).foregroundStyle(Palette.inkFaint)
        TextField(text: $query, prompt: Text(.loci("models.provider"))) { Text(.loci("models.provider")) }
          .textFieldStyle(.plain)
          .font(.system(size: 15))
          .focused($searching)
      }
      .padding(.horizontal, Spacing.m)
      .frame(height: 52)
      .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
          ForEach(found, id: \.self) { preset in
            PresetTile(preset: preset, have: preset != .custom && added.contains(preset)) {
              choose(preset)
              dismiss()
            }
          }
        }
        .padding(Spacing.s)
      }
      .frame(maxHeight: 360)
    }
    .frame(width: 520)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Palette.surface.ignoresSafeArea())
    .onAppear { searching = true }
  }

  private var found: [ModelPreset] {
    let words = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !words.isEmpty else { return ModelPreset.allCases }
    return ModelPreset.allCases.filter { preset in
      ModelWords.searchable(preset).contains { $0.lowercased().contains(words) }
    }
  }
}

private struct PresetTile: View {
  let preset: ModelPreset
  let have: Bool
  let choose: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: choose) {
      VStack(spacing: Spacing.xs) {
        ModelMark(preset: preset, size: 38)
        ModelWords.name(preset).font(.system(size: 12)).foregroundStyle(Palette.ink).lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 14)
      .padding(.bottom, Spacing.s)
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering && !have ? Palette.fillStrong : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .disabled(have)
    .opacity(have ? 0.35 : 1)
    .onHover { hovering = $0 }
  }
}
