import LociModel
import SwiftUI

/// Picks what a conversation runs on: a row of agents, the models the chosen one offers, and how hard it thinks.
/// The models come from what the agent listed last, so the list is there at once.
struct RuntimePicker<Footer: View>: View {
  let runtime: Runtime
  let installations: [AgentInstallation]
  /// Whether thinking is chosen here too; a row that shows it beside the picker leaves it out.
  var choosesEffort = true
  let change: (Runtime) -> Void
  @ViewBuilder var footer: () -> Footer
  @State private var models: Feed<[AgentModel]>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      agents
      Hairline().padding(.vertical, 6)
      ScrollView {
        VStack(spacing: 0) {
          if runtime.provider != .bundledPi {
            row(nil, Text(.loci("agents.anyModel")))
          }
          ForEach(Agents.offered(models?.value ?? [], keeping: runtime.model), id: \.id) { model in
            row(model.id, Text(verbatim: model.name))
          }
          if models?.value == nil { ProgressView().controlSize(.small).padding(.vertical, 8) }
        }
      }
      .scrollIndicators(.never)
      .frame(maxHeight: 300)
      .fixedSize(horizontal: false, vertical: true)
      if choosesEffort, !runtime.provider.efforts.isEmpty {
        Hairline().padding(.vertical, 6)
        HStack(spacing: 10) {
          Text(.loci("conversation.thinking")).font(.system(size: 12.5)).foregroundStyle(Palette.inkMuted)
          Spacer(minLength: 0)
          EffortPicker(provider: runtime.provider, effort: runtime.effort) { effort in
            change(Runtime(provider: runtime.provider, model: runtime.model, effort: effort))
          }
        }
        .padding(.horizontal, 6)
      }
      footer()
    }
    .padding(8)
    .frame(width: 320)
    .subscribing(AgentModelList(runtime.provider), into: $models)
  }

  private var agents: some View {
    HStack(spacing: 2) {
      ForEach(Agents.choosable(installations, keeping: runtime.provider), id: \.self) { provider in
        let chosen = provider == runtime.provider
        Button {
          guard !chosen else { return }
          change(Runtime(provider: provider, effort: runtime.effort))
        } label: {
          AgentMark(provider: provider, size: 20)
            .saturation(chosen ? 1 : 0)
            .opacity(chosen ? 1 : 0.7)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(chosen ? Palette.tint : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(Agents.label(of: provider)))
        .accessibilityLabel(Text(Agents.label(of: provider)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
      }
    }
  }

  private func row(_ model: String?, _ name: Text) -> some View {
    let chosen = model == runtime.model
    return Button {
      change(Runtime(provider: runtime.provider, model: model, effort: runtime.effort))
    } label: {
      HStack(spacing: 8) {
        name.font(.system(size: 13, weight: chosen ? .semibold : .regular))
          .foregroundStyle(model == nil ? Palette.inkMuted : Palette.ink)
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: Symbols.done).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
          .opacity(chosen ? 1 : 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(MenuRowStyle(chosen: chosen))
  }
}

extension RuntimePicker where Footer == EmptyView {
  init(
    runtime: Runtime, installations: [AgentInstallation], choosesEffort: Bool = true,
    change: @escaping (Runtime) -> Void
  ) {
    self.init(
      runtime: runtime, installations: installations, choosesEffort: choosesEffort, change: change,
      footer: { EmptyView() })
  }
}

/// How hard the agent thinks, in words, from leaving it to the agent to the most the provider offers.
struct EffortPicker: View {
  let provider: Provider
  let effort: ThinkingEffort?
  let change: (ThinkingEffort?) -> Void

  var body: some View {
    CapsulePicker(
      selection: Binding {
        effort
      } set: {
        change($0)
      },
      options: [(ThinkingEffort?.none, LocalizedStringResource.loci("agents.anyModel"))]
        + provider.efforts.map { (ThinkingEffort?.some($0), Agents.effortName($0)) },
      compact: true)
  }
}

/// A row of a menu Loci draws itself: washed under the pointer, tinted when chosen.
struct MenuRowStyle: ButtonStyle {
  var chosen = false

  func makeBody(configuration: Configuration) -> some View {
    RowBody(configuration: configuration, chosen: chosen)
  }

  private struct RowBody: View {
    let configuration: Configuration
    let chosen: Bool
    @State private var hovering = false

    var body: some View {
      configuration.label
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(chosen ? Palette.tint : hovering || configuration.isPressed ? Palette.fill : .clear)
        )
        .onHover { hovering = $0 }
    }
  }
}

/// A rule between parts of a popover.
struct Hairline: View {
  var body: some View {
    Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline)
  }
}
