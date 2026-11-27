import LociModel
import SwiftUI

/// Beside the send button: the agent, model and thinking this conversation runs on, always in view. It opens the
/// picker; a dot marks a conversation that chose its own rather than its kind's default.
struct RuntimeCapsule: View {
  let conversation: ConversationRef
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @State private var use: Feed<RuntimeInUse>?
  @State private var installations: [AgentInstallation] = []
  @State private var open = false
  @State private var hovering = false

  var body: some View {
    if let use = use?.value {
      Button {
        open.toggle()
      } label: {
        RuntimeLabel(runtime: use.runtime, showsEffort: true)
          .padding(.leading, 9)
          .padding(.trailing, 12)
          .frame(height: Size.composerButton)
          .background(
            Capsule(style: .circular).fill(open ? Palette.surface : hovering ? Palette.fillStrong : Palette.fill)
          )
          .overlay { if open { Capsule(style: .circular).strokeBorder(Palette.accent, lineWidth: 1.5) } }
          .overlay(alignment: .topTrailing) {
            if use.isOwn { Circle().fill(Palette.accent).frame(width: 6, height: 6).offset(x: -3, y: 2) }
          }
          .contentShape(Capsule(style: .circular))
      }
      .buttonStyle(.plain)
      .onHover { hovering = $0 }
      .changesData()
      .popover(isPresented: $open, arrowEdge: .top) {
        RuntimePicker(runtime: use.runtime, installations: installations, change: choose) {
          if use.isOwn { footer(kindDefault: use.kindDefault, own: use.runtime) }
        }
        .task { installations = (try? await host.run(DetectAgents())) ?? [] }
      }
      .subscribing(ConversationRuntime(conversation), into: $use)
    } else if case .unavailable(.olderMac) = use {
      Image(systemName: Symbols.retry).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.inkMuted)
        .frame(width: Size.composerButton, height: Size.composerButton)
        .help(Text(.loci("error.olderMac")))
        .subscribing(ConversationRuntime(conversation), into: $use)
    } else {
      Color.clear.frame(width: 0, height: Size.composerButton)
        .subscribing(ConversationRuntime(conversation), into: $use)
    }
  }

  private func footer(kindDefault: Runtime, own: Runtime) -> some View {
    VStack(spacing: 6) {
      Hairline().padding(.top, 6)
      HStack(spacing: 6) {
        Button {
          Task { _ = try? await host.run(SetConversationRuntime(nil, for: conversation)) }
        } label: {
          HStack(spacing: 7) {
            Image(systemName: Symbols.undo).font(.system(size: 11, weight: .medium))
            RuntimeLabel(runtime: kindDefault, showsEffort: true, muted: true)
          }
          .padding(.horizontal, 8)
          .frame(height: 30)
          .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
        .help(Text(.loci("runtime.followDefault")))
        Spacer(minLength: 0)
        Button(.loci("runtime.makeDefault")) {
          Task { await chooseRuntime(own, for: .kind(conversation.kind), on: host, openPlace: openPlace) }
        }
        .buttonStyle(AmberButtonStyle())
      }
    }
  }

  private func choose(_ runtime: Runtime) {
    Task { await chooseRuntime(runtime, for: .conversation(conversation), on: host, openPlace: openPlace) }
  }
}

/// An agent's mark, the model's name as the agent shows it, and how hard it thinks.
struct RuntimeLabel: View {
  let runtime: Runtime
  var showsEffort = false
  var muted = false
  @State private var models: Feed<[AgentModel]>?

  var body: some View {
    HStack(spacing: 7) {
      AgentMark(provider: runtime.provider, size: muted ? 14 : 16)
      Group {
        if let model = runtime.model {
          Text(verbatim: models?.value?.first { $0.id == model }?.name ?? Agents.modelName(model))
        } else {
          Text(Agents.label(of: runtime.provider))
        }
      }
      .font(.system(size: muted ? 12 : 12.5, weight: muted ? .regular : .semibold))
      .foregroundStyle(muted ? Palette.inkMuted : Palette.ink)
      .lineLimit(1)
      if showsEffort, let effort = runtime.effort {
        Text(Agents.effortName(effort)).font(.system(size: 12)).foregroundStyle(Palette.inkMuted).lineLimit(1)
      }
    }
    .subscribing(runtime.model == nil ? nil : AgentModelList(runtime.provider), into: $models)
  }
}

/// Adds a file to what is about to be sent.
struct AttachButton: View {
  let attach: () -> Void

  var body: some View {
    Button(action: attach) {
      Image(systemName: Symbols.add).font(.system(size: 17, weight: .regular)).foregroundStyle(Palette.inkMuted)
    }
    .buttonStyle(RoundGlyphStyle())
    .help(Text(.loci("talk.addFile")))
    .accessibilityLabel(Text(.loci("talk.addFile")))
  }
}
