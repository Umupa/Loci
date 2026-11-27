import LociModel
import SwiftUI

/// What the companion runs on, one row for each kind of conversation: the agent and model, and how hard it thinks.
/// Conversations that chose their own sit under their kind and can go back to it. Background work runs on the
/// tool model.
struct ModelsTab: View {
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @State private var defaults: Feed<RuntimeDefaults>?
  @State private var options: Feed<ModelOptions>?
  @State private var installations: [AgentInstallation] = []

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    VStack(spacing: 0) {
      if let defaults = defaults?.value {
        ForEach(Array(defaults.kinds.enumerated()), id: \.element.kind) { index, kind in
          RuntimeRow(
            runtime: kind.runtime, installations: installations,
            change: { choose($0, for: .kind(kind.kind)) }
          ) {
            KindTitle(kind: kind.kind)
          }
          .rule(index > 0)
          ForEach(defaults.own.filter { $0.conversation.kind == kind.kind }, id: \.conversation) { own in
            RuntimeRow(
              runtime: own.runtime, installations: installations, own: true,
              change: { choose($0, for: .conversation(own.conversation)) },
              revert: { Task { _ = try? await host.run(SetConversationRuntime(nil, for: own.conversation)) } }
            ) {
              Label {
                Text(verbatim: own.title).lineLimit(1).truncationMode(.middle)
              } icon: {
                Image(systemName: Symbols.notes).font(.system(size: 11))
              }
              .font(.system(size: 13))
              .foregroundStyle(Palette.inkMuted)
            }
            .rule(true)
          }
        }
        BackgroundRow(options: options?.value).rule(true)
      } else if case .unavailable(.olderMac) = defaults {
        Text(.loci("error.olderMac")).font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
          .frame(maxWidth: .infinity, alignment: .leading).padding(16)
      }
    }
    .background(Palette.surface)
    .clipShape(shape)
    .cardShadow(shape)
    .frame(maxWidth: 820, alignment: .leading)
    .subscribing(RuntimeOverview(), into: $defaults)
    .subscribing(AvailableModels(), into: $options)
    .task { installations = (try? await host.run(DetectAgents())) ?? [] }
  }

  private func choose(_ runtime: Runtime, for target: RuntimeTarget) {
    Task { await chooseRuntime(runtime, for: target, on: host, openPlace: openPlace) }
  }
}

/// One row: what it is for, the model it runs on, and how hard it thinks. A conversation's own is lighter, indented
/// under its kind, and can follow the kind again.
private struct RuntimeRow<Title: View>: View {
  let runtime: Runtime
  let installations: [AgentInstallation]
  var own = false
  let change: (Runtime) -> Void
  var revert: (() -> Void)?
  @ViewBuilder let title: () -> Title
  @State private var open = false

  var body: some View {
    HStack(spacing: 16) {
      title().frame(maxWidth: .infinity, alignment: .leading)
      Button {
        open.toggle()
      } label: {
        PopupLabel { RuntimeLabel(runtime: runtime, muted: own).frame(width: 196, alignment: .leading) }
          .frame(width: 230, alignment: .leading)
      }
      .buttonStyle(.plain)
      .changesData()
      .popover(isPresented: $open, arrowEdge: .bottom) {
        RuntimePicker(runtime: runtime, installations: installations, choosesEffort: false, change: change)
      }
      HStack(spacing: 6) {
        if !runtime.provider.efforts.isEmpty {
          EffortPicker(provider: runtime.provider, effort: runtime.effort) { effort in
            change(Runtime(provider: runtime.provider, model: runtime.model, effort: effort))
          }
          .changesData()
        }
        if let revert {
          Button(action: revert) {
            Image(systemName: Symbols.undo).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.inkMuted)
              .frame(width: 24, height: 24).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(Text(.loci("runtime.followDefault")))
          .changesData()
        }
      }
      .frame(width: 360, alignment: .trailing)
    }
    .padding(.leading, own ? 66 : 16)
    .padding(.trailing, 16)
    .frame(height: own ? 46 : 62)
  }
}

/// A kind of conversation: its symbol on a tile and its name.
private struct KindTitle: View {
  let kind: ConversationKind

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: Self.symbol(kind)).font(.system(size: 15)).foregroundStyle(Palette.ink)
        .frame(width: 36, height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well))
      Text(Self.name(kind)).font(.system(size: 15, weight: .semibold))
    }
  }

  static func symbol(_ kind: ConversationKind) -> String {
    switch kind {
    case .main: Symbols.ask
    case .item: Symbols.library
    case .course: Symbols.course
    case .project: Symbols.project
    }
  }

  static func name(_ kind: ConversationKind) -> LocalizedStringResource {
    switch kind {
    case .main: .loci("runtime.main")
    case .item: .loci("runtime.items")
    case .course: .loci("runtime.courses")
    case .project: .loci("runtime.projects")
    }
  }
}

/// Background work: the tool model, chosen from what the model services offer.
private struct BackgroundRow: View {
  let options: ModelOptions?
  @Environment(\.host) private var host

  var body: some View {
    HStack(spacing: 16) {
      HStack(spacing: 14) {
        Image(systemName: Symbols.schedule).font(.system(size: 15)).foregroundStyle(Palette.ink)
          .frame(width: 36, height: 36)
          .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well))
        Text(.loci("runtime.background")).font(.system(size: 15, weight: .semibold))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      ModelChoiceMenu(
        groups: options?.groups ?? [],
        selection: Binding {
          options?.toolModel
        } set: { choice in
          Task { await setToolModel(choice) }
        }
      )
      .frame(width: 230, alignment: .leading)
      Color.clear.frame(width: 360, height: 1)
    }
    .padding(.horizontal, 16)
    .frame(height: 62)
  }

  private func setToolModel(_ choice: ModelChoice?) async {
    guard let access = await host.modelSettingsAccess(), var settings = try? await access.readModelSettings().settings
    else { return }
    settings.toolModel = choice
    _ = try? await access.saveModelSettings(settings)
  }
}
