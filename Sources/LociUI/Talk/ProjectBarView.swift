import LociModel
import SwiftUI

/// What the project bar asks of the page around it.
struct ProjectBarActions {
  let open: (Home) -> Void
  let start: () -> Void
  let rename: (Project.ID, String) -> Void
  let reicon: (Project.ID, String) -> Void
  let pin: (Project.ID, String, Bool) -> Void
  let remember: (Project.ID, Bool) -> Void
  let archive: (Project.ID) -> Void
  let delete: (Project.ID) -> Void
}

/// The glass bar centred over the companion's page: the chat, each project's symbol, then `+` and `⌄`. The
/// open one expands smoothly to its name under a single gliding slider; excess projects fold into `⌄`.
struct ProjectBarView: View {
  let bar: ProjectBar
  let home: Home
  /// Width available to the bar before overflow projects fold into the list.
  var maxWidth: CGFloat = Size.projectBarWidest
  /// The blank seal of a new project not yet in the bar, while there is one.
  var newSeal: NewSeal?
  /// The symbols new projects' words suggested, worn faintly until they are named.
  var suggested: [Project.ID: String] = [:]
  /// How many next-up cards each seal caught; a new one stamps it.
  var stamps: [Home: Int] = [:]
  let actions: ProjectBarActions
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  @Environment(\.locale) private var locale
  @State private var listing = false
  @State private var renaming: Project.ID?
  @State private var reiconing: Project.ID?

  private var plan: ProjectBarPlan {
    ProjectBarPlan.compute(
      projects: bar.projects, home: home, drafting: drafting, availableWidth: maxWidth,
      chatLabel: localized("projects.chat"))
  }

  private var drafting: Bool { newSeal != nil }

  private var hiddenUnseen: Bool {
    plan.hidden.contains { bar.unseen.contains($0.id) }
  }

  var body: some View {
    let plan = self.plan
    HStack(spacing: ProjectBarPlan.spacing) {
      chatTab
      barDivider
      ForEach(plan.visible, id: \.id) { project in
        let open = home == .project(project.id) && !drafting
        ProjectTab(
          bar: bar, project: project, open: open, unseen: !open && bar.unseen.contains(project.id),
          nameWidth: plan.openNameWidth, stamp: stamps[.project(project.id)] ?? 0,
          suggested: suggested[project.id], actions: actions
        )
        .id(project.id)
        .transition(reduceMotion ? .identity : .opacity)
      }
      if let newSeal {
        TabPill(open: true, action: {}) { _ in
          UnnamedSeal(project: nil, symbol: newSeal.landed ? newSeal.symbol : nil, working: newSeal.sent)
            .opacity(newSeal.sent && !newSeal.landed ? 0 : 1)
            .anchorPreference(key: NextUpAnchors.self, value: .bounds) { NextUpAnchors.Value(newSeal: $0) }
        }
        .transition(reduceMotion ? .identity : .scale(scale: 0.4).combined(with: .opacity))
      }
      if drafting || !plan.visible.isEmpty {
        barDivider
      }
      BarIconButton(symbol: Symbols.add, help: .loci("projects.new"), action: actions.start)
        .disabled(!changesAllowed || drafting)
        .opacity(drafting ? 0.45 : 1)
      UnfoldButton(overflow: plan.overflowCount, unseen: hiddenUnseen) { listing.toggle() }
        .popover(isPresented: $listing, arrowEdge: .bottom) {
          ProjectList(bar: bar, home: home, actions: actions) { chosen in
            listing = false
            actions.open(chosen)
          } start: {
            listing = false
            actions.start()
          }
        }
    }
    .backgroundPreferenceValue(ActiveTabAnchor.self) { anchor in
      GeometryReader { proxy in
        if let anchor {
          let rect = proxy[anchor]
          Capsule(style: .circular)
            .fill(Palette.surface)
            .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
            .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
        }
      }
      .allowsHitTesting(false)
    }
    .padding(ProjectBarPlan.outerPadding)
    .glassEffect(.regular, in: Capsule(style: .circular))
    .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .animation(reduceMotion ? nil : Motion.pageTurn, value: home)
    .animation(reduceMotion ? nil : Motion.slider, value: plan.visible.map(\.id))
    .animation(reduceMotion ? nil : Motion.newSeal, value: drafting)
  }

  private var barDivider: some View {
    Rectangle()
      .fill(Palette.lineStrong)
      .frame(width: Size.hairline, height: 16)
      .padding(.horizontal, 4)
  }

  private var chatTab: some View {
    let open = home == .chat && !drafting
    return TabPill(open: open, action: { actions.open(.chat) }) { hovering in
      Text(.loci("projects.chat"))
        .font(.system(size: 13.5, weight: open ? .semibold : .medium))
        .foregroundStyle(open || hovering ? Palette.ink : Palette.inkMuted)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .keyframeAnimator(initialValue: 1.0, trigger: stamps[.chat] ?? 0) { label, scale in
          label.scaleEffect(scale)
        } keyframes: { _ in
          SpringKeyframe(1.3, duration: 0.16)
          SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
        }
    }
    .sealAnchor(.chat)
  }

  private func localized(_ key: String.LocalizationValue) -> String {
    var resource = LocalizedStringResource.loci(key)
    resource.locale = locale
    return String(localized: resource)
  }
}

private struct ActiveTabAnchor: PreferenceKey {
  static let defaultValue: Anchor<CGRect>? = nil

  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = nextValue() ?? value
  }
}

/// One tab in the project bar: reports its bounds to the sliding capsule when open, and shows a quiet hover
/// wash otherwise.
struct TabPill<Face: View>: View {
  let open: Bool
  let action: () -> Void
  @ViewBuilder let face: (Bool) -> Face
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      face(hovering)
        .padding(.horizontal, 3)
        .frame(minWidth: ProjectBarPlan.sealTabWidth, minHeight: ProjectBarPlan.tabHeight)
        .background {
          Capsule(style: .circular)
            .fill(Palette.fill)
            .opacity(!open && hovering ? 1 : 0)
        }
        .contentShape(Capsule(style: .circular))
    }
    .buttonStyle(PressStyle(scale: 0.95))
    .onHover { hovering = $0 }
    .anchorPreference(key: ActiveTabAnchor.self, value: .bounds) { open ? $0 : nil }
  }
}

private struct BarIconButton: View {
  let symbol: String
  let help: LocalizedStringResource
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
        .frame(width: ProjectBarPlan.addButtonWidth, height: ProjectBarPlan.tabHeight)
        .background(Circle().fill(hovering ? Palette.fill : .clear))
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .onHover { hovering = $0 }
    .help(Text(help))
  }
}

/// Opens the full project list; shows a compact count and amber dot when overflow projects are folded off the bar.
private struct UnfoldButton: View {
  let overflow: Int
  let unseen: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 3) {
        if overflow > 0 {
          Text(verbatim: "+\(overflow)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        Image(systemName: Symbols.unfold)
          .font(.system(size: overflow > 0 ? 10.5 : 12, weight: .semibold))
      }
      .foregroundStyle(hovering ? Palette.ink : Palette.inkMuted)
      .padding(.horizontal, overflow > 0 ? 7 : 0)
      .frame(
        minWidth: overflow > 0 ? nil : ProjectBarPlan.unfoldButtonWidth,
        minHeight: ProjectBarPlan.tabHeight
      )
      .frame(height: ProjectBarPlan.tabHeight)
      .background(Capsule(style: .circular).fill(hovering ? Palette.fill : .clear))
      .overlay(alignment: .topTrailing) {
        if unseen {
          Circle()
            .fill(Palette.accent)
            .frame(width: 5.5, height: 5.5)
            .offset(x: -3, y: 4)
        }
      }
      .contentShape(Capsule(style: .circular))
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .onHover { hovering = $0 }
    .help(Text(.loci("projects.all")))
  }
}

/// A new project's seal before it is in the bar: blank while the words are written, then circled while they
/// are on their way, wearing the symbol they suggested once the large seal has flown into it.
struct NewSeal: Equatable {
  var sent = false
  var landed = false
  var symbol: String?
}

/// An amber light circling a shape while the companion sets up a new project.
struct TurningRing<Ring: InsettableShape>: View {
  let shape: Ring
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let turns = reduceMotion ? 0.14 : context.date.timeIntervalSinceReferenceDate / Self.period
      shape
        .strokeBorder(
          AngularGradient(
            stops: [
              .init(color: .clear, location: 0), .init(color: .clear, location: 0.55),
              .init(color: Palette.accent, location: 0.85), .init(color: .clear, location: 1),
            ], center: .center, angle: .degrees(turns.truncatingRemainder(dividingBy: 1) * 360)),
          lineWidth: 1.6)
    }
    .allowsHitTesting(false)
  }

  static var period: Double { 1.5 }
}

/// A faint warm light just under the bar while a project is being made: a little wider than the bar, fading out
/// before it reaches the conversation.
struct WarmLight: View {
  let on: Bool
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      Ellipse()
        .fill(EllipticalGradient(colors: [Palette.glow, Palette.glow.opacity(0)], center: .center))
        .frame(width: proxy.size.width * 1.3, height: Self.height)
        .phaseAnimator(on && !reduceMotion ? [1.0, 1.08] : [1.0]) { light, spread in
          light.scaleEffect(x: spread, y: 1)
        } animation: { _ in
          .easeInOut(duration: 1.6)
        }
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2 + Self.drop)
    }
    .opacity(on ? 1 : 0)
    .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: on)
    .allowsHitTesting(false)
  }

  static let height: CGFloat = 120
  /// How far below the bar's middle the light's middle sits.
  static let drop: CGFloat = 30
}
