import LociModel
import SwiftUI

/// Beside the send button: the agent, model and thinking this conversation runs on, which opens the runtime island.
/// Folds to the agent's mark alone in a companion pane.
struct RuntimeCapsule: View {
  let conversation: ConversationRef
  var compact = false
  @Binding var islandOpen: Bool
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.standIns) private var standIns
  @State private var use: Feed<RuntimeInUse>?
  @State private var models: Feed<[AgentModel]>?
  @State private var hovering = false

  static let longestLabel: CGFloat = 210

  private var active: Bool { islandOpen || standIns?.runtimeIsland != nil }

  var body: some View {
    if let use = use?.value {
      HStack(spacing: compact ? 5 : 3) {
        Button {
          let target = !islandOpen
          withAnimation(reduceMotion ? nil : (target ? Motion.islandOpen : Motion.islandClose)) {
            islandOpen = target
          }
        } label: {
          face(use: use)
        }
        .buttonStyle(IslandTriggerStyle(reducesMotion: reduceMotion))
        .onHover { hovering = $0 }
        .help(helpText(for: use.runtime))
        .changesData()
        .anchorPreference(key: RuntimeIslandAnchors.self, value: .bounds) { RuntimeIslandAnchors(trigger: $0) }
        Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline, height: 14)
      }
      .subscribing(ConversationRuntime(conversation), into: $use)
      .subscribing(use.runtime.model == nil ? nil : AgentModelList(use.runtime.provider), into: $models)
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

  @ViewBuilder
  private func face(use: RuntimeInUse) -> some View {
    let lit = active || hovering
    if compact {
      AgentMark(provider: use.runtime.provider, size: 15.5, plain: true)
        .frame(width: Size.composerButton, height: Size.composerButton)
        .background(
          Circle().fill(
            use.isOwn ? (lit ? Palette.accent.opacity(0.22) : Palette.tint) : (lit ? Palette.fillStrong : Palette.fill))
        )
        .contentShape(Circle())
    } else {
      RuntimeLabel(runtime: use.runtime, showsEffort: true, accented: use.isOwn)
        .padding(.horizontal, use.isOwn ? 9 : 8)
        .frame(height: 28)
        .frame(maxWidth: Self.longestLabel)
        .fixedSize()
        .background {
          if use.isOwn {
            Capsule(style: .circular).fill(lit ? Palette.accent.opacity(0.22) : Palette.tint)
          } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(lit ? Palette.fillStrong : .clear)
          }
        }
        .contentShape(Rectangle())
    }
  }

  private func helpText(for runtime: Runtime) -> Text {
    let model = modelSummary(for: runtime)
    if let effort = runtime.effort {
      return Text(joining: model, Text(verbatim: " · "), Text(Agents.effortName(effort)))
    }
    return model
  }

  private func modelSummary(for runtime: Runtime) -> Text {
    if let model = runtime.model {
      let raw = models?.value?.first { $0.id == model }?.name ?? Agents.modelName(model)
      return Text(verbatim: Agents.splitModelTag(raw).title)
    }
    return Text(Agents.label(of: runtime.provider))
  }
}

private struct IslandTriggerStyle: ButtonStyle {
  let reducesMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(reducesMotion || !configuration.isPressed ? 1 : 0.93)
      .animation(reducesMotion ? nil : Motion.islandTouch, value: configuration.isPressed)
  }
}

/// The foot of the runtime island while a conversation runs on its own choice: back to the kind's default, or make
/// this choice the default.
struct RuntimeOverrideFooter: View {
  let conversation: ConversationRef
  let kindDefault: Runtime
  let own: Runtime
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @Environment(\.changesAllowed) private var changesAllowed

  var body: some View {
    HStack(spacing: 6) {
      Button {
        Task { _ = try? await host.run(SetConversationRuntime(nil, for: conversation)) }
      } label: {
        HStack(spacing: 5) {
          Image(systemName: Symbols.undo).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.inkMuted)
          RuntimeLabel(runtime: kindDefault, showsEffort: true, muted: true)
        }
        .padding(.horizontal, 6)
        .frame(height: 25)
        .contentShape(Rectangle())
      }
      .buttonStyle(MenuRowStyle())
      .help(Text(.loci("runtime.followDefault")))
      Spacer(minLength: 4)
      Button(.loci("runtime.makeDefault")) {
        Task {
          await chooseRuntime(
            own, for: .kind(conversation.kind), on: host, changesAllowed: changesAllowed, openPlace: openPlace)
        }
      }
      .buttonStyle(QuietFootButtonStyle())
    }
  }
}

/// A quiet bordered action at the foot of a card, which does not shout with the accent.
struct QuietFootButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    FootBody(configuration: configuration)
  }

  private struct FootBody: View {
    let configuration: Configuration
    @State private var hovering = false

    var body: some View {
      configuration.label
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(hovering || configuration.isPressed ? Palette.fillStrong : Palette.fill)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(
            Palette.lineStrong, lineWidth: Size.hairline)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
  }
}

/// An agent's bare mark, the clean model name without capability suffixes, and thinking effort when chosen.
struct RuntimeLabel: View {
  let runtime: Runtime
  var showsEffort = false
  var muted = false
  var accented = false
  @State private var models: Feed<[AgentModel]>?

  var body: some View {
    HStack(spacing: 6) {
      AgentMark(provider: runtime.provider, size: muted ? 13 : 15, plain: true)
      Group {
        if let model = runtime.model {
          let raw = models?.value?.first { $0.id == model }?.name ?? Agents.modelName(model)
          Text(verbatim: Agents.splitModelTag(raw).title)
        } else {
          Text(Agents.label(of: runtime.provider))
        }
      }
      .font(.system(size: muted ? 11.5 : 12.5, weight: muted ? .regular : .medium))
      .foregroundStyle(muted ? Palette.inkMuted : Palette.ink)
      .lineLimit(1)
      if showsEffort, let effort = runtime.effort {
        Text(Agents.effortName(effort))
          .font(.system(size: muted ? 11.5 : 12, weight: .regular))
          .foregroundStyle(accented ? Palette.accentInk : Palette.inkMuted)
          .lineLimit(1)
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
