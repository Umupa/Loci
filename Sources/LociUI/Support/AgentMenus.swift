import AppKit
import LociModel
import SwiftUI

/// The plus button in the field at the foot of a conversation, opening a menu: adding a file, then what
/// Loci runs on, the agent, the model and thinking effort, each a submenu. What Loci runs on is one setting
/// for the whole app.
struct RuntimeMenu: View {
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @Environment(\.colorScheme) private var scheme
  /// Whether the agent can be chosen here too, or only the model and thinking.
  let choosesAgent: Bool
  /// What adding a file does; without it the menu has no such item.
  var attach: (() -> Void)?
  @State private var runtime: Feed<Runtime>?
  @State private var equipment: Feed<MediaSetup>?
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
    .subscribing(MediaSettings(), into: $equipment)
    .task(id: piInstallation) {
      installations = (try? await host.run(DetectAgents())) ?? []
    }
    .task(id: modelRequest) {
      guard let request = modelRequest else { return }
      models = []
      let found = (try? await host.run(AgentModels(provider: request.runtime.provider))) ?? []
      if !Task.isCancelled { models = found }
    }
  }

  private var piInstallation: ComponentStatus.Installation? {
    equipment?.value?.components.first { $0.component == .bundledPi }?.installation
  }

  private struct ModelRequest: Hashable {
    let runtime: Runtime
    let installation: ComponentStatus.Installation?
  }

  private var modelRequest: ModelRequest? {
    runtime?.value.map { ModelRequest(runtime: $0, installation: $0.provider == .bundledPi ? piInstallation : nil) }
  }

  @ViewBuilder private func choices(_ current: Runtime) -> some View {
    if choosesAgent {
      Picker(selection: provider(current)) {
        ForEach(Agents.choosable(installations, keeping: current.provider), id: \.self) { provider in
          Label {
            Text(Agents.label(of: provider))
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
      if current.provider != .bundledPi { Text(.loci("agents.anyModel")).tag(String?.none) }
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
      if provider == .bundledPi {
        change(Runtime(provider: provider, effort: current.effort))
        return
      }
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
    Task { await chooseRuntime(runtime, on: host, openPlace: openPlace) }
  }
}

@MainActor
func chooseRuntime(_ runtime: Runtime, on host: any LociModel.Host, openPlace: OpenPlace) async {
  guard (try? await host.run(SetRuntime(runtime))) != nil, runtime.provider == .bundledPi,
    await host.modelSettingsAccess() != nil
  else { return }
  let installations = (try? await host.run(DetectAgents())) ?? []
  if !Agents.bundledPiIsReady(installations) { openPlace(.settings(.models)) }
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
