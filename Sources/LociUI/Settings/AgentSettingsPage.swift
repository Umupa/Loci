import LociModel
import SwiftUI

/// Every agent this Mac might run: which are installed and at what version, the one new mentors run on,
/// and the model each is asked for.
struct AgentSettingsPage: View {
  @Environment(\.host) private var host
  @State private var installations: [AgentInstallation]?
  @State private var defaults: AgentDefaults?
  @State private var models: [Mentor.Provider: [String]] = [:]

  var body: some View {
    SettingsPage(symbol: Symbols.agents, title: .loci("settings.agents")) {
      if let installations, let defaults {
        SettingsGroup(title: .loci("agents.newMentors"), inset: 48) {
          ForEach(Agents.installedFirst(installations), id: \.provider) { installation in
            AgentRow(installation: installation, isDefault: installation.provider == defaults.provider) {
              Task { self.defaults = try? await host.run(SetDefaultAgent(installation.provider)) }
            }
          }
        }
        let listing = installations.compactMap { installation -> Mentor.Provider? in
          guard case .installed = installation, models[installation.provider]?.isEmpty == false else { return nil }
          return installation.provider
        }
        if !listing.isEmpty {
          SettingsGroup(title: .loci("agents.defaultModels"), inset: 48) {
            ForEach(listing, id: \.self) { provider in
              SettingsRow {
                AgentMark(provider: provider)
                Text(verbatim: Agents.name(of: provider))
              } trailing: {
                PopupPicker(
                  selection: model(of: provider, in: defaults),
                  options: [(String?.none, Text(.loci("agents.anyModel")))]
                    + Agents.offered(models[provider] ?? [], keeping: defaults.models[provider]).map {
                      (String?.some($0), Text(verbatim: Agents.modelName($0)))
                    })
              }
            }
          }
        }
      } else {
        ProgressView().controlSize(.small).frame(maxWidth: .infinity)
      }
    }
    .task {
      defaults = try? await host.run(ReadAgentDefaults())
      let found = (try? await host.run(DetectAgents())) ?? []
      installations = found
      for case .installed(let installed) in found {
        models[installed.provider] = (try? await host.run(AgentModels(provider: installed.provider))) ?? []
      }
    }
  }

  private func model(of provider: Mentor.Provider, in defaults: AgentDefaults) -> Binding<String?> {
    Binding {
      defaults.models[provider]
    } set: { model in
      Task { self.defaults = try? await host.run(SetDefaultModel(provider: provider, model: model)) }
    }
  }
}

/// One agent: its mark, name and version; a check on the one new mentors run on, a green dot on the
/// others that are installed. One that is missing is greyed out.
private struct AgentRow: View {
  let installation: AgentInstallation
  let isDefault: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      SettingsRow {
        AgentMark(provider: installation.provider, faded: !isInstalled)
        Text(verbatim: Agents.name(of: installation.provider))
          .foregroundStyle(isInstalled ? Palette.ink : Palette.inkMuted)
        if let version {
          Text(verbatim: version).font(.system(size: 11).monospaced()).foregroundStyle(Palette.inkFaint)
        }
      } trailing: {
        if isDefault {
          Image(systemName: Symbols.done).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.accent)
        } else if isInstalled {
          Circle().fill(Palette.ready).frame(width: 7, height: 7)
            .background(Circle().fill(Palette.ready.opacity(0.18)).frame(width: 13, height: 13))
            .accessibilityLabel(Text(.loci("agents.installed")))
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isInstalled)
    .accessibilityAddTraits(isDefault ? .isSelected : [])
  }

  private var isInstalled: Bool {
    if case .installed = installation { true } else { false }
  }

  private var version: String? {
    guard case .installed(let found) = installation else { return nil }
    return found.version.flatMap(Agents.version)
  }
}
