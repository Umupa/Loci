import LociModel
import SwiftUI

/// Every agent this Mac might run, which are installed and at what version. What a conversation runs on is chosen
/// in its plus menu; the bundled Pi downloads here.
struct AgentSettingsPage: View {
  @Environment(\.host) private var host
  @State private var installations: [AgentInstallation]?
  @State private var options: Feed<ModelOptions>?
  @State private var equipment: Feed<MediaSetup>?

  var body: some View {
    SettingsPage(symbol: Symbols.agents, title: .loci("settings.agents")) {
      Group {
        if let installations {
          SettingsGroup(title: nil, inset: 48) {
            ForEach(Agents.installedFirst(installations), id: \.provider) { installation in
              if installation.provider == .bundledPi, let status = piStatus {
                ComponentRow(status: status, work: piWork, install: piInstall)
              } else {
                AgentRow(installation: installation)
              }
            }
          }
        } else {
          ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
      }
      .changesData()
    }
    .subscribing(AvailableModels(), into: $options)
    .subscribing(MediaSettings(), into: $equipment)
    .task(id: piStatus?.installation) { installations = (try? await host.run(DetectAgents())) ?? [] }
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
}

/// One agent's mark, name, version and whether it is installed.
private struct AgentRow: View {
  let installation: AgentInstallation

  var body: some View {
    SettingsRow {
      AgentMark(provider: installation.provider)
      Text(Agents.label(of: installation.provider))
        .foregroundStyle(isInstalled ? Palette.ink : Palette.inkMuted)
      if let version {
        Text(verbatim: version).font(.system(size: 11).monospaced()).foregroundStyle(Palette.inkMuted)
      }
    } trailing: {
      if isInstalled {
        Circle().fill(Palette.ready).frame(width: 7, height: 7)
          .background(Circle().fill(Palette.ready.opacity(0.18)).frame(width: 13, height: 13))
          .accessibilityLabel(Text(.loci("agents.installed")))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue(isInstalled ? Text(.loci("agents.installed")) : Text(.loci("agents.notInstalled")))
  }

  private var isInstalled: Bool {
    if case .installed = installation { true } else { false }
  }

  private var version: String? {
    guard case .installed(let found) = installation else { return nil }
    return found.version.flatMap(Agents.version)
  }
}
