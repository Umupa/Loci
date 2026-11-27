import LociModel
import SwiftUI

/// Which half of the runtime island is in front.
enum RuntimeIslandTab: Hashable {
  case model, effort

  /// The half shown for a runtime: thinking only while its agent can be asked how hard to think.
  func shown(for runtime: Runtime) -> RuntimeIslandTab {
    self == .effort && runtime.provider.efforts.isEmpty ? .model : self
  }
}

/// What the island does once something is picked in it.
enum RuntimeIslandStep: Equatable {
  case close
  case show(RuntimeIslandTab)

  /// A thinking effort closes the island. A model moves on to its thinking when its agent has any, else closes.
  static func after(picking runtime: Runtime, on tab: RuntimeIslandTab) -> RuntimeIslandStep {
    guard tab == .model, !runtime.provider.efforts.isEmpty else { return .close }
    return .show(.effort)
  }
}

/// Where the island sits over its conversation: just above the composer, as wide as a narrow composer and
/// right-aligned to a wide one.
struct RuntimeIslandLayout: Equatable {
  static let preferredWidth: CGFloat = 332
  static let gap: CGFloat = 10

  let minX: CGFloat
  let width: CGFloat
  /// From the bottom of the conversation to the island's bottom edge.
  let bottomInset: CGFloat

  init(composer: CGRect, height: CGFloat) {
    width = composer.width < Self.preferredWidth + 56 ? composer.width : Self.preferredWidth
    minX = composer.maxX - width
    bottomInset = height - composer.minY + Self.gap
  }

  /// The point the island grows from: straight above the trigger, on its bottom edge.
  func growthAnchor(trigger: CGRect?) -> UnitPoint {
    guard let trigger, width > 0 else { return .bottomTrailing }
    return UnitPoint(x: min(max((trigger.midX - minX) / width, 0), 1), y: 1)
  }
}

/// The frames the island is placed against, reported by the composer and its runtime trigger.
struct RuntimeIslandAnchors: PreferenceKey {
  var composer: Anchor<CGRect>?
  var trigger: Anchor<CGRect>?

  static let defaultValue = RuntimeIslandAnchors()

  static func reduce(value: inout RuntimeIslandAnchors, nextValue: () -> RuntimeIslandAnchors) {
    let next = nextValue()
    value.composer = value.composer ?? next.composer
    value.trigger = value.trigger ?? next.trigger
  }
}

/// The runtime island's face: the model and thinking halves under a sliding switch, and the way back to the kind's
/// default when this conversation runs on its own choice.
struct RuntimeIslandCard: View {
  let conversation: ConversationRef
  let use: RuntimeInUse
  let installations: [AgentInstallation]
  var width: CGFloat
  var favorites: ModelFavorites
  let close: () -> Void
  let choose: (Runtime) -> Void
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var tab: RuntimeIslandTab
  @State private var models: Feed<[AgentModel]>?
  @Namespace private var tabSpace

  init(
    conversation: ConversationRef, use: RuntimeInUse, installations: [AgentInstallation],
    width: CGFloat = RuntimeIslandLayout.preferredWidth, favorites: ModelFavorites = .shared,
    initialTab: RuntimeIslandTab = .model, close: @escaping () -> Void, choose: @escaping (Runtime) -> Void
  ) {
    self.conversation = conversation
    self.use = use
    self.installations = installations
    self.width = width
    self.favorites = favorites
    self.close = close
    self.choose = choose
    _tab = State(initialValue: initialTab)
  }

  private var shownTab: RuntimeIslandTab { tab.shown(for: use.runtime) }

  var body: some View {
    VStack(spacing: 0) {
      header
      Hairline()
      Group {
        switch shownTab {
        case .model:
          ModelFlyout(
            runtime: use.runtime, installations: installations, width: width, favorites: favorites, select: pick)
        case .effort:
          EffortMenu(
            provider: use.runtime.provider, effort: use.runtime.effort, width: width,
            select: { effort in
              pick(Runtime(provider: use.runtime.provider, model: use.runtime.model, effort: effort))
            }
          )
        }
      }
      .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
      if use.isOwn {
        Hairline()
        RuntimeOverrideFooter(conversation: conversation, kindDefault: use.kindDefault, own: use.runtime)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
      }
    }
    .frame(width: width)
    .subscribing(AgentModelList(use.runtime.provider), into: $models)
  }

  private func pick(_ runtime: Runtime) {
    let step = RuntimeIslandStep.after(picking: runtime, on: shownTab)
    choose(runtime)
    switch step {
    case .close: close()
    case .show(let next): withAnimation(reduceMotion ? nil : Motion.islandOpen) { tab = next }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      HStack(spacing: 2) {
        tabPill(.model) {
          AgentMark(provider: use.runtime.provider, size: 14, plain: true)
          modelTitle.lineLimit(1)
        }
        if !use.runtime.provider.efforts.isEmpty {
          tabPill(.effort) {
            EffortGauge(size: 12.5).foregroundStyle(effortTint)
            effortTitle.lineLimit(1)
          }
        }
      }
      .padding(3)
      .background(Capsule(style: .circular).fill(Palette.fill))
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: close) {
        Image(systemName: Symbols.cancel)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 24, height: 24)
          .background(Circle().fill(Palette.fill))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.loci("overlay.close")))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  private func tabPill<Content: View>(_ item: RuntimeIslandTab, @ViewBuilder content: () -> Content) -> some View {
    let selected = shownTab == item
    return Button {
      withAnimation(reduceMotion ? nil : Motion.islandOpen) { tab = item }
    } label: {
      HStack(spacing: 5) { content() }
        .font(.system(size: 12, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Palette.ink : Palette.inkMuted)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background {
          if selected {
            Capsule(style: .circular)
              .fill(Palette.thumb)
              .shadow(color: Palette.warmShadow.opacity(0.08), radius: 2, y: 1)
              .matchedGeometryEffect(id: "tabThumb", in: tabSpace)
          }
        }
        .contentShape(Capsule(style: .circular))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var effortTint: Color {
    guard shownTab == .effort else { return Palette.inkMuted }
    return EffortTileShimmer.color(for: use.runtime.effort) ?? Palette.inkMuted
  }

  private var modelTitle: Text {
    if let model = use.runtime.model {
      let raw = models?.value?.first { $0.id == model }?.name ?? Agents.modelName(model)
      return Text(verbatim: Agents.splitModelTag(raw).title)
    }
    return Text(Agents.label(of: use.runtime.provider))
  }

  private var effortTitle: Text {
    use.runtime.effort.map { Text(Agents.effortName($0)) } ?? Text(.loci("agents.anyModel"))
  }
}

/// Lays the runtime island over a conversation, above its composer, with the scrim that closes it.
private struct RuntimeIslandHost: ViewModifier {
  @Binding var open: Bool
  let conversation: ConversationRef?
  @Environment(\.host) private var host
  @Environment(\.openPlace) private var openPlace
  @Environment(\.standIns) private var standIns
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var use: Feed<RuntimeInUse>?
  @State private var installations: [AgentInstallation] = []

  private var isExpanded: Bool {
    guard conversation != nil, use?.value != nil else { return false }
    return open || standIns?.runtimeIsland != nil
  }

  func body(content: Content) -> some View {
    content
      .overlay {
        if isExpanded {
          Palette.islandScrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .transition(.opacity)
        }
      }
      .overlayPreferenceValue(RuntimeIslandAnchors.self) { anchors in
        GeometryReader { proxy in
          if isExpanded, let conversation, let use = use?.value, let composer = anchors.composer {
            let layout = RuntimeIslandLayout(composer: proxy[composer], height: proxy.size.height)
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            RuntimeIslandCard(
              conversation: conversation, use: use, installations: installations, width: layout.width,
              initialTab: standIns?.runtimeIsland ?? .model, close: close,
              choose: { runtime in
                Task { await chooseRuntime(runtime, for: .conversation(conversation), on: host, openPlace: openPlace) }
              }
            )
            .modifier(IslandShellStyle(shape: shape, snapshot: standIns != nil))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, layout.minX)
            .padding(.bottom, layout.bottomInset)
            .transition(
              reduceMotion
                ? .opacity
                : .scale(scale: 0.4, anchor: layout.growthAnchor(trigger: anchors.trigger.map { proxy[$0] }))
                  .combined(with: .opacity)
            )
          }
        }
      }
      .onKeyPress(.escape) {
        guard isExpanded else { return .ignored }
        close()
        return .handled
      }
      .subscribing(conversation.map(ConversationRuntime.init), into: $use)
      .task { installations = (try? await host.run(DetectAgents())) ?? [] }
      .onChange(of: conversation) { open = false }
  }

  private func close() {
    withAnimation(reduceMotion ? nil : Motion.islandClose) { open = false }
  }
}

private struct IslandShellStyle: ViewModifier {
  let shape: RoundedRectangle
  let snapshot: Bool

  func body(content: Content) -> some View {
    if snapshot {
      content
        .background(shape.fill(Palette.menuFace))
        .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        .cardShadow(shape)
    } else {
      content.glassPanel(in: shape)
    }
  }
}

extension View {
  /// Lays the runtime island over this conversation while `open`, placed against the composer this view reports
  /// through `RuntimeIslandAnchors`.
  func runtimeIsland(open: Binding<Bool>, conversation: ConversationRef?) -> some View {
    modifier(RuntimeIslandHost(open: open, conversation: conversation))
  }
}
