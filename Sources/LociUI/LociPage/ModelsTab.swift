import LociModel
import SwiftUI

/// What the companion runs on: a row per kind of conversation with its model and thinking, the conversations that
/// chose otherwise hanging under their kind, and the background model last.
struct ModelsTab: View {
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var defaults: Feed<RuntimeDefaults>?
  @State private var options: Feed<ModelOptions>?
  @State private var installations: [AgentInstallation] = []

  fileprivate static let modelColumn: CGFloat = 196
  fileprivate static let effortColumn: CGFloat = 104
  fileprivate static let revertColumn: CGFloat = 26
  fileprivate static let inset: CGFloat = 16
  fileprivate static let kindRow: CGFloat = 58
  fileprivate static let ownRow: CGFloat = 44
  fileprivate static let kindTile: CGFloat = 35
  fileprivate static let threadReach: CGFloat = 16
  fileprivate static let threadX = inset + kindTile / 2 - 0.5

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    VStack(spacing: 0) {
      if let defaults = defaults?.value {
        ForEach(Array(defaults.kinds.enumerated()), id: \.element.kind) { index, kind in
          let owns = defaults.own.filter { $0.conversation.kind == kind.kind }
          if index > 0 { Hairline().opacity(0.6) }
          RuntimeRow(
            runtime: kind.runtime, installations: installations, hasChildren: !owns.isEmpty,
            change: { choose($0, for: .kind(kind.kind)) }
          ) {
            KindTitle(kind: kind.kind)
          }
          ForEach(Array(owns.enumerated()), id: \.element.conversation) { ownIndex, own in
            RuntimeRow(
              runtime: own.runtime, installations: installations, own: true,
              lastOwn: ownIndex == owns.count - 1, firstOwn: ownIndex == 0,
              change: { choose($0, for: .conversation(own.conversation)) },
              revert: { Task { _ = try? await host.run(SetConversationRuntime(nil, for: own.conversation)) } }
            ) {
              OwnTitle(kind: own.conversation.kind, title: own.title)
            }
          }
        }
        BackgroundRow(options: options?.value)
      } else if case .unavailable(.olderMac) = defaults {
        Text(.loci("error.olderMac")).font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
          .frame(maxWidth: .infinity, alignment: .leading).padding(16)
      }
    }
    .background(Palette.surface)
    .clipShape(shape)
    .cardShadow(shape)
    .frame(maxWidth: 680, alignment: .leading)
    .subscribing(RuntimeOverview(), into: $defaults)
    .subscribing(AvailableModels(), into: $options)
    .task { installations = (try? await host.run(DetectAgents())) ?? [] }
  }

  private func choose(_ runtime: Runtime, for target: RuntimeTarget) {
    Task { await chooseRuntime(runtime, for: target, on: host, changesAllowed: changesAllowed, openPlace: openPlace) }
  }
}

/// One row: who runs, the model, the thinking, and the way back to the default for a conversation's own choice.
private struct RuntimeRow<Title: View>: View {
  let runtime: Runtime
  let installations: [AgentInstallation]
  var own = false
  var hasChildren = false
  var lastOwn = false
  var firstOwn = false
  let change: (Runtime) -> Void
  var revert: (() -> Void)?
  @ViewBuilder let title: () -> Title
  @State private var modelOpen = false
  @State private var effortOpen = false
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 12) {
      title().frame(maxWidth: .infinity, alignment: .leading)

      Button {
        modelOpen.toggle()
      } label: {
        PlainTriggerLabel(muted: own, open: modelOpen) {
          RuntimeLabel(runtime: runtime, muted: own)
        }
      }
      .buttonStyle(.plain)
      .frame(width: ModelsTab.modelColumn, alignment: .leading)
      .changesData()
      .popover(isPresented: $modelOpen, arrowEdge: .bottom) {
        ModelFlyout(runtime: runtime, installations: installations) { picked in
          change(picked)
          modelOpen = false
        }
      }

      Group {
        if !runtime.provider.efforts.isEmpty {
          Button {
            effortOpen.toggle()
          } label: {
            PlainTriggerLabel(muted: own, open: effortOpen) {
              EffortGauge(size: 13)
                .foregroundStyle(own && !effortOpen ? Palette.inkFaint : Palette.inkMuted)
              Group {
                if let effort = runtime.effort {
                  Text(Agents.effortName(effort))
                } else {
                  Text(.loci("agents.anyModel"))
                }
              }
              .font(.system(size: 12.5, weight: own ? .regular : .medium))
              .lineLimit(1)
            }
          }
          .buttonStyle(.plain)
          .changesData()
          .popover(isPresented: $effortOpen, arrowEdge: .bottom) {
            EffortMenu(
              provider: runtime.provider, effort: runtime.effort,
              select: { effort in
                change(Runtime(provider: runtime.provider, model: runtime.model, effort: effort))
              },
              onPick: { effortOpen = false })
          }
        } else {
          Color.clear.frame(height: 30)
        }
      }
      .frame(width: ModelsTab.effortColumn, alignment: .leading)

      Group {
        if let revert {
          RevertButton(activeRow: hovering, action: revert)
            .changesData()
        } else {
          Color.clear.frame(height: 24)
        }
      }
      .frame(width: ModelsTab.revertColumn, alignment: .center)
    }
    .padding(.horizontal, ModelsTab.inset)
    .frame(height: own ? ModelsTab.ownRow : ModelsTab.kindRow)
    .background {
      if own && hovering {
        Palette.fill.opacity(0.65)
      }
    }
    .overlay(alignment: .topLeading) { thread }
    .overlay(alignment: .topLeading) {
      if own && !firstOwn {
        Hairline().opacity(0.6).padding(.leading, 56)
      }
    }
    .onHover { hovering = $0 }
  }

  @ViewBuilder
  private var thread: some View {
    if !own, hasChildren {
      let tileBottom = (ModelsTab.kindRow + ModelsTab.kindTile) / 2
      Rectangle()
        .fill(Palette.lineStrong)
        .frame(width: 1, height: ModelsTab.kindRow - tileBottom)
        .offset(x: ModelsTab.threadX, y: tileBottom)
    } else if own {
      let middle = ModelsTab.ownRow / 2
      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Palette.lineStrong)
          .frame(width: 1, height: lastOwn ? middle + 0.5 : ModelsTab.ownRow)
          .offset(x: ModelsTab.threadX)
        Rectangle()
          .fill(Palette.lineStrong)
          .frame(width: ModelsTab.threadReach, height: 1)
          .offset(x: ModelsTab.threadX, y: middle)
      }
    }
  }
}

private struct OwnTitle: View {
  let kind: ConversationKind
  let title: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: Self.symbol(kind))
        .font(.system(size: 12))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 16)
      Text(verbatim: title)
        .font(.system(size: 13))
        .foregroundStyle(Palette.inkMuted)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(.leading, ModelsTab.threadX - ModelsTab.inset + ModelsTab.threadReach + 7)
  }

  private static func symbol(_ kind: ConversationKind) -> String {
    switch kind {
    case .main: Symbols.ask
    case .item: Symbols.notes
    case .course: Symbols.course
    case .project: Symbols.project
    }
  }
}

private struct RevertButton: View {
  let activeRow: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: Symbols.undo)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(hovering ? Palette.ink : activeRow ? Palette.inkMuted : Palette.inkFaint)
        .frame(width: 24, height: 24)
        .background(Circle().fill(hovering ? Palette.fillStrong : .clear))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(Text(.loci("runtime.followDefault")))
  }
}

/// A kind of conversation: its symbol on a tile and its name.
private struct KindTitle: View {
  let kind: ConversationKind

  var body: some View {
    HStack(spacing: 13) {
      Image(systemName: Self.symbol(kind)).font(.system(size: 15)).foregroundStyle(Palette.ink)
        .frame(width: ModelsTab.kindTile, height: ModelsTab.kindTile)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.well))
      Text(Self.name(kind)).font(.system(size: 14.5, weight: .semibold))
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

/// Background work: the tool model, on the well under the rows, in the same column as their models.
private struct BackgroundRow: View {
  let options: ModelOptions?
  @Environment(\.host) private var host

  var body: some View {
    VStack(spacing: 0) {
      Hairline()
      HStack(spacing: 12) {
        HStack(spacing: 13) {
          Image(systemName: Symbols.schedule).font(.system(size: 15)).foregroundStyle(Palette.ink)
            .frame(width: ModelsTab.kindTile, height: ModelsTab.kindTile)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface))
            .overlay(
              RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
                Palette.line, lineWidth: Size.hairline)
            )
          Text(.loci("runtime.background")).font(.system(size: 14.5, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        ModelChoiceMenu(
          groups: options?.groups ?? [],
          selection: Binding {
            options?.toolModel
          } set: { choice in
            Task { await setToolModel(choice) }
          },
          plain: true
        )
        .frame(width: ModelsTab.modelColumn, alignment: .leading)

        Color.clear.frame(width: ModelsTab.effortColumn, height: 1)
        Color.clear.frame(width: ModelsTab.revertColumn, height: 1)
      }
      .padding(.horizontal, ModelsTab.inset)
      .frame(height: ModelsTab.kindRow)
      .background(Palette.well)
    }
  }

  private func setToolModel(_ choice: ModelChoice?) async {
    guard let access = await host.modelSettingsAccess(), var settings = try? await access.readModelSettings().settings
    else { return }
    settings.toolModel = choice
    _ = try? await access.saveModelSettings(settings)
  }
}
