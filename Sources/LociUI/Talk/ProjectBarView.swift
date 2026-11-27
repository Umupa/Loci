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
  /// A project being started shows as a dashed symbol until it has its name.
  var starting = false
  /// Whether the new project's words have already been sent to the companion.
  var startingSent = false
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
      projects: bar.projects, home: home, starting: starting, availableWidth: maxWidth,
      chatLabel: localized("projects.chat"), newProjectLabel: localized("projects.new"))
  }

  private var hiddenUnseen: Bool {
    plan.hidden.contains { bar.unseen.contains($0.id) }
  }

  var body: some View {
    let plan = self.plan
    HStack(spacing: ProjectBarPlan.spacing) {
      chatTab
      barDivider
      if starting {
        ghostTab
      }
      ForEach(plan.visible, id: \.id) { project in
        let open = home == .project(project.id) && !starting
        ProjectTab(
          bar: bar, project: project, open: open, unseen: !open && bar.unseen.contains(project.id),
          nameWidth: plan.openNameWidth, stamp: stamps[.project(project.id)] ?? 0, actions: actions
        )
        .id(project.id)
        .transition(reduceMotion ? .identity : .opacity)
      }
      if starting || !plan.visible.isEmpty {
        barDivider
      }
      BarIconButton(symbol: Symbols.add, help: .loci("projects.new"), action: actions.start)
        .disabled(!changesAllowed || starting)
        .opacity(starting ? 0.45 : 1)
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
            .overlay { if starting && startingSent { TurningCapsule() } }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
        }
      }
      .allowsHitTesting(false)
    }
    .padding(ProjectBarPlan.outerPadding)
    .glassEffect(.regular, in: Capsule(style: .circular))
    .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .animation(reduceMotion ? nil : Motion.slider, value: home)
    .animation(reduceMotion ? nil : Motion.slider, value: plan.visible.map(\.id))
    .animation(reduceMotion ? nil : Motion.quick, value: starting)
  }

  private var barDivider: some View {
    Rectangle()
      .fill(Palette.lineStrong)
      .frame(width: Size.hairline, height: 16)
      .padding(.horizontal, 4)
  }

  private var chatTab: some View {
    let open = home == .chat && !starting
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

  private var ghostTab: some View {
    TabPill(open: true, action: {}) { _ in
      HStack(spacing: 0) {
        ProjectSeal(symbol: "", ghost: true)
        Text(.loci("projects.new"))
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(Palette.inkFaint)
          .lineLimit(1)
          .padding(.horizontal, 6)
      }
    }
  }

  private func localized(_ key: String.LocalizationValue) -> String {
    var resource = LocalizedStringResource.loci(key)
    resource.locale = locale
    return String(localized: resource)
  }
}

private struct ProjectTab: View {
  let bar: ProjectBar
  let project: Project
  let open: Bool
  let unseen: Bool
  let nameWidth: CGFloat
  let stamp: Int
  let actions: ProjectBarActions
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  @State private var heldWidth: CGFloat?
  @State private var renaming = false
  @State private var reiconing = false

  var body: some View {
    let revealWidth =
      (open ? max(nameWidth, 1) : (heldWidth ?? Size.projectNameWidest)) + ProjectBarPlan.openLabelPadding
    TabPill(open: open, action: { actions.open(.project(project.id)) }) { hovering in
      HStack(spacing: 0) {
        ProjectSeal(symbol: project.symbol, selected: open || hovering, locked: !project.remembered, unseen: unseen)
          .scaleEffect(!open && hovering && !reduceMotion ? 1.06 : 1)
          .sealAnchor(.project(project.id))
          .keyframeAnimator(initialValue: 1.0, trigger: stamp) { seal, scale in
            seal.scaleEffect(scale)
          } keyframes: { _ in
            SpringKeyframe(1.3, duration: 0.16)
            SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
          }
        RevealWidth(fraction: open ? 1 : 0, maxWidth: revealWidth) {
          Text(verbatim: project.shownName)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
        }
        .opacity(open ? 1 : 0)
        .clipped()
        .accessibilityHidden(!open)
      }
    }
    .accessibilityLabel(Text(verbatim: project.shownName))
    .help(Text(verbatim: project.shownName))
    .onAppear { if open, nameWidth > 0 { heldWidth = nameWidth } }
    .onChange(of: open) { if open, nameWidth > 0 { heldWidth = nameWidth } }
    .onChange(of: nameWidth) { if open, nameWidth > 0 { heldWidth = nameWidth } }
    .contextMenu {
      if changesAllowed {
        ProjectMenuItems(bar: bar, project: project, actions: actions) {
          renaming = true
        } reicon: {
          reiconing = true
        }
      }
    }
    .popover(isPresented: $renaming, arrowEdge: .bottom) {
      RenameField(name: project.shownName) { name in
        renaming = false
        actions.rename(project.id, name)
      }
    }
    .popover(isPresented: $reiconing, arrowEdge: .bottom) {
      ProjectIconPicker(selected: project.symbol) { icon in
        reiconing = false
        actions.reicon(project.id, icon)
      }
    }
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
private struct TabPill<Face: View>: View {
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

/// An amber light circling the ghost capsule while the companion sets up a new project.
private struct TurningCapsule: View {
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let turns = reduceMotion ? 0.14 : context.date.timeIntervalSinceReferenceDate / Self.period
      Capsule(style: .circular)
        .strokeBorder(
          AngularGradient(
            stops: [
              .init(color: .clear, location: 0), .init(color: .clear, location: 0.58),
              .init(color: Palette.accent, location: 0.78), .init(color: Palette.Glow.gold, location: 0.85),
              .init(color: Palette.accent, location: 0.92), .init(color: .clear, location: 1),
            ], center: .center, angle: .degrees(turns.truncatingRemainder(dividingBy: 1) * 360)),
          lineWidth: 1.5)
    }
    .allowsHitTesting(false)
  }

  static let period = 2.4
}
