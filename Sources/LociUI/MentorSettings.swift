import LociModel
import SwiftUI

/// One mentor's settings: the agent and model it runs on, and how much it may do without asking.
struct MentorSettings: View {
  @Environment(\.host) private var host
  @Environment(\.dismiss) private var dismiss
  let mentor: Mentor
  let failed: (HostError) -> Void
  @State private var provider: Mentor.Provider
  @State private var model: String
  @State private var permission: Mentor.Permission
  @State private var installations: [AgentInstallation] = []

  init(mentor: Mentor, failed: @escaping (HostError) -> Void) {
    self.mentor = mentor
    self.failed = failed
    _provider = State(initialValue: mentor.provider)
    _model = State(initialValue: mentor.model ?? "")
    _permission = State(initialValue: mentor.permission)
  }

  var body: some View {
    Form {
      Section {
        Picker(selection: $provider) {
          ForEach(Agents.choosable(installations, keeping: provider), id: \.self) { provider in
            Text(verbatim: Agents.name(of: provider)).tag(provider)
          }
        } label: {
          Text(.loci("agents.provider"))
        }
        TextField(text: $model, prompt: Text(.loci("agents.anyModel"))) {
          Text(.loci("agents.model"))
        }
        Picker(selection: $permission) {
          Text(.loci("agents.askEveryTime")).tag(Mentor.Permission.ask)
          Text(.loci("agents.fullAccess")).tag(Mentor.Permission.full)
        } label: {
          Text(.loci("agents.permission"))
        }
        .pickerStyle(.radioGroup)
      } header: {
        Text(verbatim: mentor.name)
      }
    }
    .formStyle(.grouped)
    .frame(width: Size.settingsWidth)
    .fixedSize(horizontal: false, vertical: true)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
        } label: {
          Text(.loci("dialog.cancel"))
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button(action: save) {
          Text(.loci("dialog.save"))
        }
      }
    }
    .task { installations = (try? await host.run(DetectAgents())) ?? [] }
  }

  private func save() {
    let command = SetMentorAgent(
      mentor: mentor.id, choice: AgentChoice(provider: provider, model: model), permission: permission)
    dismiss()
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        failed(error)
      }
    }
  }
}
