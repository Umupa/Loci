import AppKit
import LociModel
import SwiftUI

/// Changes what a mentor runs on from a chip: the agent, the model and thinking effort, or all three.
struct AgentChoiceMenu: View {
  @Environment(\.host) private var host
  @Environment(\.colorScheme) private var scheme
  let mentor: Mentor
  let parts: Parts
  @State private var installations: [AgentInstallation] = []
  @State private var models: [String] = []

  enum Parts {
    /// The agent, with its mark.
    case agent
    /// The model, and the thinking effort when the agent has one.
    case model
    /// All three, named together.
    case all
  }

  var body: some View {
    choices.changesData()
  }

  private var choices: some View {
    Menu {
      if parts != .model {
        Picker(selection: agent) {
          ForEach(Agents.choosable(installations, keeping: mentor.provider), id: \.self) { provider in
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
      }
      if parts != .agent {
        Picker(selection: model) {
          Text(.loci("agents.anyModel")).tag(String?.none)
          ForEach(Agents.offered(models, keeping: mentor.model), id: \.self) { model in
            Text(verbatim: Agents.modelName(model)).tag(String?.some(model))
          }
        } label: {
          Text(.loci("agents.model"))
        }
        .pickerStyle(.inline)
        if !mentor.provider.efforts.isEmpty {
          Picker(selection: effort) {
            Text(.loci("agents.anyModel")).tag(ThinkingEffort?.none)
            ForEach(mentor.provider.efforts, id: \.self) { effort in
              Text(Agents.effortName(effort)).tag(ThinkingEffort?.some(effort))
            }
          } label: {
            Text(.loci("conversation.thinking"))
          }
          .pickerStyle(.inline)
        }
      }
    } label: {
      label
    }
    .menuStyle(.button)
    .buttonStyle(ChipStyle())
    .menuIndicator(.hidden)
    .fixedSize()
    .task(id: mentor.provider) {
      if parts != .model { installations = (try? await host.run(DetectAgents())) ?? [] }
      if parts != .agent { models = (try? await host.run(AgentModels(provider: mentor.provider))) ?? [] }
    }
  }

  private var label: some View {
    HStack(spacing: 4) {
      if parts != .model {
        AgentMark(provider: mentor.provider, size: 16).padding(.trailing, 1)
        Text(verbatim: Agents.name(of: mentor.provider))
      }
      if parts == .all { Text(verbatim: "·") }
      if parts != .agent {
        if let model = mentor.model {
          Text(verbatim: Agents.modelName(model))
        } else {
          Text(.loci("agents.anyModel"))
        }
      }
      if parts == .model, let effort = mentor.effort {
        Text(verbatim: "·")
        Text(Agents.effortName(effort))
      }
      Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.6).padding(.leading, 1)
    }
  }

  private var agent: Binding<Mentor.Provider> {
    Binding {
      mentor.provider
    } set: { provider in
      Task {
        let defaults = try? await host.run(ReadAgentDefaults())
        change(AgentChoice(provider: provider, model: defaults?.models[provider], effort: mentor.effort))
      }
    }
  }

  private var model: Binding<String?> {
    Binding {
      mentor.model
    } set: { model in
      change(AgentChoice(provider: mentor.provider, model: model, effort: mentor.effort))
    }
  }

  private var effort: Binding<ThinkingEffort?> {
    Binding {
      mentor.effort
    } set: { effort in
      change(AgentChoice(provider: mentor.provider, model: mentor.model, effort: effort))
    }
  }

  private func change(_ choice: AgentChoice) {
    let command = SetMentorAgent(mentor: mentor.id, choice: choice)
    Task { _ = try? await host.run(command) }
  }
}

/// A quiet capsule button, darker on hover, like the chips under the input field.
struct ChipStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    ChipBody(configuration: configuration)
  }

  private struct ChipBody: View {
    let configuration: Configuration
    @State private var hovering = false

    var body: some View {
      configuration.label
        .font(Typography.control)
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Capsule().fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Capsule())
        .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
        .onHover { hovering = $0 }
    }
  }
}

extension AgentMark {
  /// The mark as a picture, for menus, which draw images but not views.
  @MainActor static func image(_ provider: Mentor.Provider, in scheme: ColorScheme) -> NSImage? {
    let renderer = ImageRenderer(content: AgentMark(provider: provider, size: 16).environment(\.colorScheme, scheme))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    return renderer.nsImage
  }
}
