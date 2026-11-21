import AppKit
import LociModel
import SwiftUI

/// The plus button in the field at the foot of a conversation, opening a menu: adding a file, then what
/// Loci runs on, the agent, the model and thinking effort, each a submenu. What Loci runs on is one setting
/// for the whole app.
struct RuntimeMenu: View {
  @Environment(\.host) private var host
  @Environment(\.colorScheme) private var scheme
  /// Whether the agent can be chosen here too, or only the model and thinking.
  let choosesAgent: Bool
  /// What adding a file does; without it the menu has no such item.
  var attach: (() -> Void)?
  @State private var runtime: Feed<Runtime>?
  @State private var installations: [AgentInstallation] = []
  @State private var models: [String] = []

  var body: some View {
    Menu {
      if let attach {
        Button(action: attach) { Text(.loci("talk.addFile")) }
      }
      if let current = runtime?.value {
        if attach != nil { Divider() }
        choices(current)
      }
    } label: {
      Image(systemName: Symbols.add)
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(Palette.inkMuted)
    }
    .menuStyle(.button)
    .buttonStyle(RoundGlyphStyle())
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel(Text(.loci("talk.add")))
    .changesData()
    .subscribing(CurrentRuntime(), into: $runtime)
    .task(id: runtime?.value?.provider) {
      guard let provider = runtime?.value?.provider else { return }
      installations = (try? await host.run(DetectAgents())) ?? []
      models = (try? await host.run(AgentModels(provider: provider))) ?? []
    }
  }

  @ViewBuilder private func choices(_ current: Runtime) -> some View {
    if choosesAgent {
      Picker(selection: provider(current)) {
        ForEach(Agents.choosable(installations, keeping: current.provider), id: \.self) { provider in
          Label {
            Text(verbatim: Agents.name(of: provider))
          } icon: {
            AgentMark.image(provider, in: scheme).map { Image(nsImage: $0).renderingMode(.original) }
          }
          .tag(provider)
        }
      } label: {
        Text(.loci("agents.provider"))
      }
      .pickerStyle(.menu)
    }
    Picker(selection: model(current)) {
      Text(.loci("agents.anyModel")).tag(String?.none)
      ForEach(Agents.offered(models, keeping: current.model), id: \.self) { model in
        Text(verbatim: Agents.modelName(model)).tag(String?.some(model))
      }
    } label: {
      Text(.loci("agents.model"))
    }
    .pickerStyle(.menu)
    if !current.provider.efforts.isEmpty {
      Picker(selection: effort(current)) {
        Text(.loci("agents.anyModel")).tag(ThinkingEffort?.none)
        ForEach(current.provider.efforts, id: \.self) { effort in
          Text(Agents.effortName(effort)).tag(ThinkingEffort?.some(effort))
        }
      } label: {
        Text(.loci("conversation.thinking"))
      }
      .pickerStyle(.menu)
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

/// A round glyph in the field at the foot of a conversation, washed on hover.
struct RoundGlyphStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    GlyphBody(configuration: configuration)
  }

  private struct GlyphBody: View {
    let configuration: Configuration
    @State private var hovering = false

    var body: some View {
      configuration.label
        .frame(width: Size.composerButton, height: Size.composerButton)
        .background(Circle().fill(hovering ? Palette.fill : .clear))
        .contentShape(Circle())
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
