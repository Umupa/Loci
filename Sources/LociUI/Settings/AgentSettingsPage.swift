import LociModel
import SwiftUI

/// What Loci runs on: every agent this Mac might run, which are installed and at what version, the one
/// chosen, and its model and thinking effort. One setting for the whole app. On the bundled Pi the model is one
/// the model services offer, and the Pi itself downloads here.
struct AgentSettingsPage: View {
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @State private var installations: [AgentInstallation]?
  @State private var runtime: Feed<Runtime>?
  @State private var options: Feed<ModelOptions>?
  @State private var equipment: Feed<MediaSetup>?
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
          SettingsGroup(title: Agents.label(of: current.provider)) {
            SettingsRow {
              Text(.loci("agents.model"))
            } trailing: {
              if current.provider == .bundledPi {
                piModel(current)
              } else {
                PopupPicker(
                  selection: model(current),
                  options: [(String?.none, Text(.loci("agents.anyModel")))]
                    + Agents.offered(models, keeping: current.model).map {
                      (String?.some($0), Text(verbatim: Agents.modelName($0)))
                    })
              }
            }
            if current.provider == .bundledPi, let status = piStatus {
              ComponentRow(status: status, work: piWork, install: piInstall)
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
    .subscribing(AvailableModels(), into: $options)
    .subscribing(MediaSettings(), into: $equipment)
    .task { installations = (try? await host.run(DetectAgents())) ?? [] }
    .task(id: runtime?.value) {
      guard let provider = runtime?.value?.provider else { return }
      models = []
      let found = (try? await host.run(AgentModels(provider: provider))) ?? []
      if !Task.isCancelled { models = found }
    }
  }

  /// The companion's model on the bundled Pi: one the model services offer, or a way to configure them.
  @ViewBuilder private func piModel(_ current: Runtime) -> some View {
    if let groups = options?.value?.groups, !groups.isEmpty {
      ModelChoiceMenu(
        groups: groups,
        selection: Binding {
          current.model.flatMap(ModelChoice.init(runtimeModel:))
        } set: { choice in
          change(Runtime(provider: .bundledPi, model: choice?.runtimeModel, effort: current.effort))
        })
    } else if options != nil {
      Button {
        openPlace(.settings(.models))
      } label: {
        Text(.loci("keypoints.configureModels"))
      }
      .buttonStyle(AmberButtonStyle())
    }
  }

  private var piStatus: ComponentStatus? {
    equipment?.value?.components.first { $0.component == .bundledPi }
  }

  private var piWork: Transfer? {
    equipment?.value?.componentWork.first { $0.component == .bundledPi }?.state
  }

  private var piInstall: (() -> Void)? {
    guard options?.value?.groups.isEmpty == false else { return nil }
    return { Task { _ = try? await host.run(InstallComponent(.bundledPi)) } }
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

/// One agent's mark, name, version and status. Installed agents can be selected.
private struct AgentRow: View {
  let installation: AgentInstallation
  let isDefault: Bool
  let choose: () -> Void

  var body: some View {
    Group {
      if isInstalled || installation.provider == .bundledPi {
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
      Text(Agents.label(of: installation.provider))
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
