import LociModel
import SwiftUI

/// The settings page for agents: what this Mac has installed, and what new mentors run on.
struct AgentSettings: View {
  @Environment(\.host) private var host
  @State private var installations: [AgentInstallation]?
  @State private var detecting = false
  @State private var provider = Mentor.Provider.pi
  @State private var model = ""
  @State private var loaded = false

  var body: some View {
    Form {
      Section {
        Picker(selection: $provider) {
          ForEach(Agents.choosable(installations ?? [], keeping: provider), id: \.self) { provider in
            Text(verbatim: Agents.name(of: provider)).tag(provider)
          }
        } label: {
          Text(.loci("agents.provider"))
        }
        TextField(text: $model, prompt: Text(.loci("agents.anyModel"))) {
          Text(.loci("agents.model"))
        }
        .onSubmit(save)
      } header: {
        Text(.loci("agents.newMentors"))
      }
      Section {
        if let installations {
          ForEach(installations, id: \.provider) { AgentRow(installation: $0) }
        } else {
          ProgressView().frame(maxWidth: .infinity)
        }
      } header: {
        HStack {
          Text(.loci("agents.onThisMac"))
          Spacer()
          Button {
            Task { await detect(again: true) }
          } label: {
            Text(.loci("agents.detectAgain"))
          }
          .disabled(detecting)
        }
      }
    }
    .formStyle(.grouped)
    .onChange(of: provider) { if loaded { save() } }
    .onDisappear { if loaded { save() } }
    .task {
      await load()
      await detect(again: false)
    }
  }

  private func load() async {
    guard let choice = try? await host.run(NewMentorAgent()) else { return }
    provider = choice.provider
    model = choice.model ?? ""
    loaded = true
  }

  private func detect(again: Bool) async {
    detecting = true
    if again { installations = nil }
    installations = try? await host.run(DetectAgents(again: again))
    detecting = false
  }

  private func save() {
    let choice = AgentChoice(provider: provider, model: model)
    Task { _ = try? await host.run(SetNewMentorAgent(choice)) }
  }
}

/// One provider: whether it is installed, where, which version, and whether it is signed in.
private struct AgentRow: View {
  let installation: AgentInstallation

  var body: some View {
    LabeledContent {
      switch installation {
      case .missing:
        Text(.loci("agents.missing")).foregroundStyle(.secondary)
      case .installed(let found):
        VStack(alignment: .trailing) {
          if let version = found.version {
            Text(verbatim: version).textSelection(.enabled)
          }
          Text(signIn(found.signIn)).foregroundStyle(.secondary)
        }
      }
    } label: {
      Text(verbatim: Agents.name(of: installation.provider))
      if case .installed(let found) = installation {
        Text(verbatim: found.executable.path(percentEncoded: false))
          .font(Typography.mono)
          .textSelection(.enabled)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }

  private func signIn(_ state: AgentInstallation.SignIn) -> LocalizedStringResource {
    switch state {
    case .signedIn: .loci("agents.signedIn")
    case .signedOut: .loci("agents.signedOut")
    case .unknown: .loci("agents.signInUnknown")
    }
  }
}
