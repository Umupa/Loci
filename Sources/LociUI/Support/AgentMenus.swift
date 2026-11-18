import AppKit
import LociModel
import SwiftUI

/// Changes what Loci runs on from a chip under the input field: the agent, the model and thinking effort.
/// It is one setting for the whole app.
struct RuntimeMenu: View {
  @Environment(\.host) private var host
  @Environment(\.colorScheme) private var scheme
  /// Whether the chip names the agent too, or only the model.
  let namesAgent: Bool
  @State private var runtime: Feed<Runtime>?
  @State private var installations: [AgentInstallation] = []
  @State private var models: [String] = []

  var body: some View {
    ZStack {
      if let current = runtime?.value { menu(current).changesData() }
    }
    .subscribing(CurrentRuntime(), into: $runtime)
  }

  private func menu(_ current: Runtime) -> some View {
    Menu {
      Picker(selection: provider(current)) {
        ForEach(Agents.choosable(installations, keeping: current.provider), id: \.self) { provider in
          Label {
            Text(verbatim: Agents.name(of: provider))
          } icon: {
            AgentMark.image(provider, in: scheme).map { Image(nsImage: $0) }
          }
          .tag(provider)
        }
      } label: {
        Text(.loci("agents.provider"))
      }
      .pickerStyle(.inline)
      Picker(selection: model(current)) {
        Text(.loci("agents.anyModel")).tag(String?.none)
        ForEach(Agents.offered(models, keeping: current.model), id: \.self) { model in
          Text(verbatim: Agents.modelName(model)).tag(String?.some(model))
        }
      } label: {
        Text(.loci("agents.model"))
      }
      .pickerStyle(.inline)
      if !current.provider.efforts.isEmpty {
        Picker(selection: effort(current)) {
          Text(.loci("agents.anyModel")).tag(ThinkingEffort?.none)
          ForEach(current.provider.efforts, id: \.self) { effort in
            Text(Agents.effortName(effort)).tag(ThinkingEffort?.some(effort))
          }
        } label: {
          Text(.loci("conversation.thinking"))
        }
        .pickerStyle(.inline)
      }
    } label: {
      label(current)
    }
    .menuStyle(.button)
    .buttonStyle(ChipStyle())
    .menuIndicator(.hidden)
    .fixedSize()
    .task(id: current.provider) {
      installations = (try? await host.run(DetectAgents())) ?? []
      models = (try? await host.run(AgentModels(provider: current.provider))) ?? []
    }
  }

  private func label(_ current: Runtime) -> some View {
    HStack(spacing: 6) {
      AgentMark(provider: current.provider, size: 16)
      HStack(spacing: Spacing.xxs) {
        if namesAgent {
          Text(verbatim: Agents.name(of: current.provider))
          Text(verbatim: "·")
        }
        if let model = current.model {
          Text(verbatim: Agents.modelName(model))
        } else {
          Text(.loci("agents.anyModel"))
        }
        if let effort = current.effort {
          Text(verbatim: "·")
          Text(Agents.effortName(effort))
        }
      }
    }
  }

  private func provider(_ current: Runtime) -> Binding<Provider> {
    Binding {
      current.provider
    } set: { provider in
      Task {
        let models = (try? await host.run(AgentModels(provider: provider))) ?? []
        let kept = current.model.flatMap { models.contains($0) ? $0 : nil }
        change(Runtime(provider: provider, model: kept, effort: current.effort))
      }
    }
  }

  private func model(_ current: Runtime) -> Binding<String?> {
    Binding {
      current.model
    } set: { model in
      change(Runtime(provider: current.provider, model: model, effort: current.effort))
    }
  }

  private func effort(_ current: Runtime) -> Binding<ThinkingEffort?> {
    Binding {
      current.effort
    } set: { effort in
      change(Runtime(provider: current.provider, model: current.model, effort: effort))
    }
  }

  private func change(_ runtime: Runtime) {
    Task { _ = try? await host.run(SetRuntime(runtime)) }
  }
}

/// A quiet button under the input field, washed on hover.
struct ChipStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    ChipBody(configuration: configuration)
  }

  private struct ChipBody: View {
    let configuration: Configuration
    @State private var hovering = false

    var body: some View {
      configuration.label
        .font(.system(size: 12))
        .foregroundStyle(Palette.inkMuted)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(hovering ? Palette.fill : .clear))
        .contentShape(RoundedRectangle(cornerRadius: Radius.row))
        .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
        .onHover { hovering = $0 }
    }
  }
}

extension AgentMark {
  /// The mark as a picture, for menus, which draw images but not views.
  @MainActor static func image(_ provider: Provider, in scheme: ColorScheme) -> NSImage? {
    let renderer = ImageRenderer(content: AgentMark(provider: provider, size: 16).environment(\.colorScheme, scheme))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    return renderer.nsImage
  }
}
