import LociModel
import SwiftUI

/// One provider on the model services page: its mark, its name, the models checked on it while folded, and its
/// switch. A provider that is on opens in place to its address, key and models.
struct ProviderRow: View {
  let provider: ModelProvider
  let model: ModelServicesModel
  @Binding var open: ModelProviderID?
  @State private var hovering = false

  var body: some View {
    VStack(spacing: 0) {
      head
      if expanded {
        ProviderDetail(provider: provider, model: model)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .clipped()
  }

  private var expanded: Bool { open == provider.id && provider.enabled }

  private var head: some View {
    HStack(spacing: Spacing.s) {
      ModelMark(preset: provider.preset, name: provider.name, faded: !provider.enabled)
      ModelWords.name(provider.preset, custom: provider.name)
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(Palette.ink)
        .opacity(provider.enabled ? 1 : 0.45)
      if provider.enabled, !expanded {
        HStack(spacing: Spacing.xxs) {
          ForEach(provider.checkedModels.prefix(3), id: \.self) { name in
            Text(verbatim: name)
              .font(.system(size: 11).monospaced())
              .foregroundStyle(Palette.inkMuted)
              .lineLimit(1)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.fill))
          }
        }
        .transition(.opacity)
      }
      Spacer(minLength: Spacing.xs)
      if provider.enabled {
        Image(systemName: Symbols.fold)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Palette.inkFaint)
          .rotationEffect(.degrees(expanded ? 90 : 0))
      }
      Toggle(isOn: enabled) { ModelWords.name(provider.preset, custom: provider.name) }
        .labelsHidden()
        .toggleStyle(AmberSwitch(small: true))
    }
    .padding(.horizontal, 12)
    .frame(height: 50)
    .background(hovering && provider.enabled ? Palette.fill : .clear)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture {
      guard provider.enabled else { return }
      withAnimation(Motion.standard) { open = expanded ? nil : provider.id }
    }
    .contextMenu {
      Button(role: .destructive) {
        withAnimation(Motion.standard) { model.remove(provider.id) }
      } label: {
        Text(.loci("models.removeProvider"))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
  }

  private var enabled: Binding<Bool> {
    Binding {
      provider.enabled
    } set: { on in
      withAnimation(Motion.standard) {
        model.change(provider.id) { $0.enabled = on }
        if !on, open == provider.id { open = nil }
      }
    }
  }
}

/// The providers that are off, folded into one line with their marks stacked; opened, one line each.
struct ProvidersOff: View {
  let providers: [ModelProvider]
  @Binding var unfolded: Bool

  var body: some View {
    HStack(spacing: Spacing.xs) {
      HStack(spacing: -4) {
        ForEach(providers.prefix(4)) { provider in
          ModelMark(preset: provider.preset, name: provider.name, size: 18, faded: true)
            .overlay {
              RoundedRectangle(cornerRadius: 5.2, style: .continuous).strokeBorder(Palette.surface, lineWidth: 1.5)
            }
        }
      }
      Text(.loci("models.off"))
      Image(systemName: Symbols.fold)
        .font(.system(size: 9, weight: .semibold))
        .rotationEffect(.degrees(unfolded ? 90 : 0))
      Spacer()
    }
    .font(.system(size: 12))
    .foregroundStyle(Palette.inkFaint)
    .padding(.horizontal, 12)
    .frame(height: 36)
    .contentShape(Rectangle())
    .onTapGesture { withAnimation(Motion.standard) { unfolded.toggle() } }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }
}

/// The last line of the providers: opens the list of providers to add.
struct AddProviderRow: View {
  let add: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: add) {
      HStack(spacing: Spacing.s) {
        Image(systemName: Symbols.add)
          .font(.system(size: 12, weight: .medium))
          .frame(width: 28, height: 28)
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.lineStrong))
        Text(.loci("models.addProvider"))
        Spacer()
      }
      .font(.system(size: 13))
      .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background(hovering ? Palette.fill : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
