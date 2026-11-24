import LociModel
import SwiftUI

/// A provider's models as chips to check, a chip to add one by its id, getting the provider's list, and trying it.
struct ModelChips: View {
  let provider: ModelProvider
  let model: ModelServicesModel
  @State private var adding = false
  @State private var newModel = ""
  @FocusState private var typing: Bool

  var body: some View {
    FlowRow(spacing: 6) {
      ForEach(provider.models, id: \.id) { entry in
        ModelChip(entry: entry) {
          model.change(provider.id) { provider in
            guard let index = provider.models.firstIndex(where: { $0.id == entry.id }) else { return }
            provider.models[index].checked.toggle()
          }
        }
        .contextMenu {
          Button {
            Task { await model.test(provider.id, model: entry.id) }
          } label: {
            Text(.loci("models.test"))
          }
          Button(role: .destructive) {
            model.change(provider.id) { $0.models.removeAll { $0.id == entry.id } }
          } label: {
            Text(.loci("models.removeModel"))
          }
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
      }
      if fetching {
        ForEach(0..<3, id: \.self) { _ in
          Shimmer().frame(width: 96, height: 28).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      addChip
      tool(Symbols.fetchModels, .loci("models.fetch"), spinning: fetching) {
        Task { await model.fetch(provider.id) }
      }
      tool(Symbols.tryModel, .loci("models.test"), spinning: trial == .running) {
        Task { await model.test(provider.id) }
      }
      if let trial { TrialResult(trial: trial) }
    }
    .animation(Motion.standard, value: provider.models)
    .animation(Motion.standard, value: fetching)
  }

  private var fetching: Bool { model.fetching.contains(provider.id) }

  private var trial: ModelServicesModel.Trial? {
    model.latestTrial(of: provider.id)
  }

  @ViewBuilder private var addChip: some View {
    if adding {
      TextField(text: $newModel, prompt: Text(.loci("models.modelID"))) { Text(.loci("models.modelID")) }
        .textFieldStyle(.plain)
        .font(.system(size: 12).monospaced())
        .focused($typing)
        .frame(width: 130)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.accentLine))
        .onSubmit(addModel)
        .onExitCommand {
          newModel = ""
          adding = false
        }
        .onChange(of: typing) { _, now in
          if !now { addModel() }
        }
    } else {
      Button {
        adding = true
        typing = true
      } label: {
        Image(systemName: Symbols.add)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Palette.inkFaint)
          .frame(width: 28, height: 28)
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.lineStrong))
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .help(Text(.loci("models.addModel")))
      .accessibilityLabel(Text(.loci("models.addModel")))
    }
  }

  private func addModel() {
    let id = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
    newModel = ""
    adding = false
    guard !id.isEmpty else { return }
    model.change(provider.id) { provider in
      if let index = provider.models.firstIndex(where: { $0.id == id }) {
        provider.models[index].checked = true
      } else {
        provider.models.append(ProviderModel(id: id, checked: true))
      }
    }
  }

  private func tool(
    _ symbol: String, _ label: LocalizedStringResource, spinning: Bool, action: @escaping () -> Void
  ) -> some View {
    ModelTool(symbol: symbol, label: label, spinning: spinning, action: action)
  }
}

/// One model: a check box and its id, washed in amber when checked.
private struct ModelChip: View {
  let entry: ProviderModel
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(entry.checked ? Palette.accent : .clear)
          .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .strokeBorder(entry.checked ? .clear : Palette.lineStrong, lineWidth: 1)
          }
          .overlay {
            Image(systemName: Symbols.done)
              .font(.system(size: 8, weight: .heavy))
              .foregroundStyle(Palette.onAccent)
              .scaleEffect(entry.checked ? 1 : 0.5)
              .opacity(entry.checked ? 1 : 0)
          }
          .frame(width: 14, height: 14)
        Text(verbatim: entry.id)
          .font(.system(size: 12).monospaced())
          .foregroundStyle(entry.checked ? Palette.ink : Palette.inkMuted)
          .lineLimit(1)
      }
      .padding(.leading, 7)
      .padding(.trailing, 10)
      .frame(height: 28)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(entry.checked ? Palette.tint : Palette.fill)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(entry.checked ? Palette.accentLine : .clear, lineWidth: Size.hairline)
      }
      .contentShape(Rectangle())
      .animation(.spring(duration: 0.25, bounce: 0.4), value: entry.checked)
    }
    .buttonStyle(PressStyle())
    .accessibilityAddTraits(entry.checked ? .isSelected : [])
  }
}

/// A small icon button beside the models, turning while it works.
private struct ModelTool: View {
  let symbol: String
  let label: LocalizedStringResource
  let spinning: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .symbolEffect(.rotate, isActive: spinning && symbol == Symbols.fetchModels)
        .symbolEffect(.pulse, isActive: spinning && symbol != Symbols.fetchModels)
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle())
    .disabled(spinning)
    .onHover { hovering = $0 }
    .help(Text(label))
    .accessibilityLabel(Text(label))
  }
}

/// How trying went: the time it took in green, or why it failed in red.
private struct TrialResult: View {
  let trial: ModelServicesModel.Trial

  var body: some View {
    switch trial {
    case .running:
      EmptyView()
    case .took(let duration):
      Label {
        Text(verbatim: "\(Int((duration / .milliseconds(1)).rounded())) ms")
      } icon: {
        Image(systemName: Symbols.done)
      }
      .font(.system(size: 11.5).monospaced())
      .foregroundStyle(Palette.ready)
      .transition(.move(edge: .leading).combined(with: .opacity))
    case .failed(let reason):
      Label {
        Text(verbatim: reason).lineLimit(2)
      } icon: {
        Image(systemName: Symbols.failed)
      }
      .font(.system(size: 11.5))
      .foregroundStyle(Palette.failure)
      .frame(maxWidth: 300, alignment: .leading)
      .transition(.opacity)
    }
  }
}
