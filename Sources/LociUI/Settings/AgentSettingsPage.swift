import LociModel
import SwiftUI

/// What Loci runs on: every agent this Mac might run, which are installed and at what version, the one
/// chosen, and its model and thinking effort. One setting for the whole app.
struct AgentSettingsPage: View {
  @Environment(\.host) private var host
  @State private var installations: [AgentInstallation]?
  @State private var runtime: Feed<Runtime>?
  @State private var models: [String] = []

  var body: some View {
    SettingsPage(symbol: Symbols.agents, title: .loci("settings.agents")) {
      Group {
        if let installations, let current = runtime?.value {
          SettingsGroup(title: .loci("agents.runsOn"), inset: 48) {
            ForEach(Agents.installedFirst(installations), id: \.provider) { installation in
              AgentRow(installation: installation, isDefault: installation.provider == current.provider) {
                change(Runtime(provider: installation.provider))
              }
            }
          }
          SettingsGroup(title: LocalizedStringResource(stringLiteral: Agents.name(of: current.provider))) {
            SettingsRow {
              Text(.loci("agents.model"))
            } trailing: {
              PopupPicker(
                selection: model(current),
                options: [(String?.none, Text(.loci("agents.anyModel")))]
                  + Agents.offered(models, keeping: current.model).map {
                    (String?.some($0), Text(verbatim: Agents.modelName($0)))
                  })
            }
            if !current.provider.efforts.isEmpty {
              SettingsRow {
                Text(.loci("conversation.thinking"))
              } trailing: {
                PopupPicker(
                  selection: effort(current),
                  options: [(ThinkingEffort?.none, Text(.loci("agents.anyModel")))]
                    + current.provider.efforts.map { (ThinkingEffort?.some($0), Text(Agents.effortName($0))) })
              }
            }
          }
        } else {
          ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
      }
      .changesData()
    }
    .subscribing(CurrentRuntime(), into: $runtime)
    .task { installations = (try? await host.run(DetectAgents())) ?? [] }
    .task(id: runtime?.value?.provider) {
      guard let provider = runtime?.value?.provider else { return }
      models = (try? await host.run(AgentModels(provider: provider))) ?? []
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

/// One agent's mark, name, version and status. Installed agents can be selected.
private struct AgentRow: View {
  let installation: AgentInstallation
  let isDefault: Bool
  let choose: () -> Void

  var body: some View {
    Group {
      if isInstalled {
        Button(action: choose) { row.contentShape(Rectangle()) }
          .buttonStyle(.plain)
      } else {
        row
          .accessibilityElement(children: .combine)
          .accessibilityValue(Text(.loci("agents.notInstalled")))
      }
    }
    .accessibilityAddTraits(isDefault ? .isSelected : [])
  }

  private var row: some View {
    SettingsRow {
      AgentMark(provider: installation.provider)
      Text(verbatim: Agents.name(of: installation.provider))
        .foregroundStyle(isInstalled ? Palette.ink : Palette.inkMuted)
      if let version {
        Text(verbatim: version).font(.system(size: 11).monospaced()).foregroundStyle(Palette.inkMuted)
      }
    } trailing: {
      if isDefault {
        Image(systemName: Symbols.done).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.accentInk)
      } else if isInstalled {
        Circle().fill(Palette.ready).frame(width: 7, height: 7)
          .background(Circle().fill(Palette.ready.opacity(0.18)).frame(width: 13, height: 13))
          .accessibilityLabel(Text(.loci("agents.installed")))
      }
    }
  }

  private var isInstalled: Bool {
    if case .installed = installation { true } else { false }
  }

  private var version: String? {
    guard case .installed(let found) = installation else { return nil }
    return found.version.flatMap(Agents.version)
  }
}
