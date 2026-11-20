import AppKit
import LociModel
import SwiftUI

/// Over the key points: what they are picked with, how many, and picking them again.
struct KeyPointChoiceBar: View {
  @Binding var choice: KeyPointChoice
  let picking: Bool
  let pick: () -> Void

  var body: some View {
    HStack(spacing: Spacing.xs) {
      KeyPointRuntimeMenu(
        runtime: Binding {
          choice.runtime
        } set: {
          choice = KeyPointChoice(runtime: $0, count: choice.count)
        })
      Menu {
        Picker(
          selection: Binding {
            choice.count
          } set: {
            choice = KeyPointChoice(runtime: choice.runtime, count: $0)
          }
        ) {
          ForEach(KeyPointCount.allCases, id: \.self) { count in
            Text(KeyPointWords.count(count)).tag(count)
          }
        } label: {
          EmptyView()
        }
        .pickerStyle(.inline)
      } label: {
        PopupLabel { Text(KeyPointWords.count(choice.count)) }
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      Spacer(minLength: 0)
      Button(action: pick) {
        Image(systemName: Symbols.restart)
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: Size.iconButton, height: Size.iconButton)
          .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Palette.fill))
          .overlay(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(
              Palette.lineStrong, lineWidth: Size.hairline)
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(PressStyle())
      .disabled(picking)
      .opacity(picking ? 0.4 : 1)
      .help(Text(.loci("keypoints.pickAgain")))
      .accessibilityLabel(Text(.loci("keypoints.pickAgain")))
    }
  }
}

/// The face of a popup: its value with the up-and-down chevrons, on a raised capsule.
struct PopupLabel<Label: View>: View {
  @ViewBuilder let label: () -> Label
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 6) {
      label()
      Image(systemName: Symbols.popup).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Palette.inkFaint)
    }
    .font(.system(size: 12.5))
    .foregroundStyle(Palette.ink)
    .lineLimit(1)
    .padding(.leading, 9)
    .padding(.trailing, 8)
    .frame(height: 26)
    .background(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(hovering ? Palette.fillStrong : Palette.fill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline)
    )
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }
}

/// The runtime key points are picked with: following Loci, or an agent and model of their own.
private struct KeyPointRuntimeMenu: View {
  @Environment(\.host) private var host
  @Environment(\.colorScheme) private var scheme
  @Binding var runtime: Runtime?
  @State private var loci: Feed<Runtime>?
  @State private var installations: [AgentInstallation] = []
  @State private var models: [String] = []

  var body: some View {
    let shown = runtime ?? loci?.value
    Menu {
      Button {
        runtime = nil
      } label: {
        if runtime == nil { Image(systemName: Symbols.done) }
        Text(.loci("keypoints.followLoci"))
      }
      Divider()
      Picker(selection: provider) {
        ForEach(Agents.choosable(installations, keeping: shown?.provider ?? .codex), id: \.self) { provider in
          Label {
            Text(verbatim: Agents.name(of: provider))
          } icon: {
            AgentMark.image(provider, in: scheme).map { Image(nsImage: $0).renderingMode(.original) }
          }
          .tag(Provider?.some(provider))
        }
      } label: {
        Text(.loci("agents.provider"))
      }
      .pickerStyle(.inline)
      if let runtime {
        Picker(selection: model(runtime)) {
          Text(.loci("agents.anyModel")).tag(String?.none)
          ForEach(Agents.offered(models, keeping: runtime.model), id: \.self) { model in
            Text(verbatim: Agents.modelName(model)).tag(String?.some(model))
          }
        } label: {
          Text(.loci("agents.model"))
        }
        .pickerStyle(.inline)
      }
    } label: {
      PopupLabel {
        if let shown { AgentMark(provider: shown.provider, size: 15) }
        if runtime == nil {
          Text(.loci("keypoints.followLoci"))
        } else if let shown {
          Text(verbatim: Agents.name(of: shown.provider))
          if let model = shown.model {
            Text(verbatim: Agents.modelName(model)).font(.system(size: 11.5).monospaced()).foregroundStyle(
              Palette.inkMuted)
          }
        }
      }
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .subscribing(CurrentRuntime(), into: $loci)
    .task(id: runtime?.provider) {
      installations = (try? await host.run(DetectAgents())) ?? []
      if let provider = runtime?.provider {
        models = (try? await host.run(AgentModels(provider: provider))) ?? []
      }
    }
  }

  private var provider: Binding<Provider?> {
    Binding {
      runtime?.provider
    } set: { provider in
      runtime = provider.map { Runtime(provider: $0) }
    }
  }

  private func model(_ current: Runtime) -> Binding<String?> {
    Binding {
      current.model
    } set: { model in
      runtime = Runtime(provider: current.provider, model: model, effort: current.effort)
    }
  }
}
