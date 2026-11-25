import LociModel
import SwiftUI

/// What the project bar asks of the page around it.
struct ProjectBarActions {
  let open: (Home) -> Void
  let start: () -> Void
  let rename: (Project.ID, String) -> Void
  let pin: (Project.ID, String, Bool) -> Void
  let remember: (Project.ID, Bool) -> Void
  let archive: (Project.ID) -> Void
  let delete: (Project.ID) -> Void
}

/// The glass bar centred over the companion's page: the chat with the companion's face, a seal for each
/// project, then `+` and `⌄`. The open one spreads out to its name, and the slider under it follows; a project
/// with something new carries an amber dot, one kept out of memory a lock.
struct ProjectBarView: View {
  let bar: ProjectBar
  let home: Home
  /// A project being started shows as a dashed seal until it has its name.
  var starting = false
  /// How many next-up cards each seal caught; a new one stamps it.
  var stamps: [Home: Int] = [:]
  let actions: ProjectBarActions
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed
  @Namespace private var slider
  @State private var listing = false
  @State private var renaming: Project.ID?

  var body: some View {
    HStack(spacing: 2) {
      tab(for: .chat, label: Text(.loci("projects.chat"))) { LociAvatar(size: Size.seal) }
      Rectangle().fill(Palette.lineStrong).frame(width: Size.hairline, height: 18).padding(.horizontal, 4)
      if starting {
        tab(for: nil, label: Text(.loci("projects.new")).foregroundStyle(Palette.inkFaint)) {
          ProjectSeal(seal: "", ghost: true)
        }
      }
      ForEach(bar.projects, id: \.id) { project in
        projectTab(project)
          .transition(reduceMotion ? .identity : .scale(scale: 1.6).combined(with: .opacity))
      }
      iconButton("plus", help: .loci("projects.new"), action: actions.start)
        .disabled(!changesAllowed)
      iconButton("chevron.down", help: .loci("projects.all")) { listing.toggle() }
        .popover(isPresented: $listing, arrowEdge: .bottom) {
          ProjectList(bar: bar, home: home) { chosen in
            listing = false
            actions.open(chosen)
          } start: {
            listing = false
            actions.start()
          }
        }
    }
    .padding(4)
    .glassEffect(.regular, in: Capsule(style: .circular))
    .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: home)
    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6), value: bar.projects.map(\.id))
    .animation(reduceMotion ? nil : Motion.standard, value: starting)
  }

  private func projectTab(_ project: Project) -> some View {
    tab(for: .project(project.id), label: Text(verbatim: project.shownName), dot: bar.unseen.contains(project.id)) {
      ProjectSeal(seal: project.seal, locked: !project.remembered)
    }
    .help(Text(verbatim: project.shownName))
    .contextMenu { if changesAllowed { menu(for: project) } }
    .popover(
      isPresented: Binding(get: { renaming == project.id }, set: { if !$0 { renaming = nil } }), arrowEdge: .bottom
    ) {
      RenameField(name: project.shownName) { name in
        renaming = nil
        actions.rename(project.id, name)
      }
    }
  }

  @ViewBuilder private func menu(for project: Project) -> some View {
    Button(.loci("projects.rename"), systemImage: "pencil") { renaming = project.id }
    Menu(.loci("projects.pin")) {
      ForEach(bar.panels[project.id] ?? [], id: \.name) { panel in
        Toggle(
          panel.title,
          isOn: Binding(
            get: { project.pinned.contains(panel.name) },
            set: { actions.pin(project.id, panel.name, $0) }))
      }
    }
    .disabled((bar.panels[project.id] ?? []).isEmpty)
    Toggle(
      String(localized: .loci("projects.forget")),
      isOn: Binding(get: { !project.remembered }, set: { actions.remember(project.id, !$0) }))
    Divider()
    Button(.loci("projects.archive"), systemImage: "archivebox") { actions.archive(project.id) }
    Button(.loci("projects.delete"), systemImage: "trash", role: .destructive) { actions.delete(project.id) }
  }

  /// One item of the bar; `nil` is the project being started, which cannot be chosen.
  private func tab<Mark: View>(
    for target: Home?, label: Text, dot: Bool = false, @ViewBuilder mark: () -> Mark
  ) -> some View {
    let open = target.map { $0 == home && !starting } ?? starting
    return Button {
      if let target { actions.open(target) }
    } label: {
      HStack(spacing: 0) {
        mark()
          .sealAnchor(target)
          .keyframeAnimator(initialValue: 1.0, trigger: target.flatMap { stamps[$0] } ?? 0) { seal, scale in
            seal.scaleEffect(scale)
          } keyframes: { _ in
            SpringKeyframe(1.3, duration: 0.16)
            SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
          }
        if open {
          label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
        }
      }
      .padding(.horizontal, 5)
      .frame(minWidth: 32, minHeight: 32)
      .background {
        if open {
          Capsule(style: .circular).fill(Palette.surface)
            .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
            .overlay(Capsule(style: .circular).strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
            .matchedGeometryEffect(id: "slider", in: slider)
        }
      }
      .overlay(alignment: .topLeading) {
        if dot && !open {
          Circle().fill(Palette.accent).frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Palette.canvas, lineWidth: 2).padding(-2))
            .offset(x: 22, y: 4)
        }
      }
      .contentShape(Capsule(style: .circular))
    }
    .buttonStyle(PressStyle(scale: 0.95))
  }

  private func iconButton(_ symbol: String, help: LocalizedStringResource, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 32, height: 32)
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle(scale: 0.92))
    .help(Text(help))
  }
}

/// A project's new name, typed where its seal is.
private struct RenameField: View {
  @State var name: String
  let done: (String) -> Void
  @FocusState private var focused: Bool

  init(name: String, done: @escaping (String) -> Void) {
    _name = State(initialValue: name)
    self.done = done
  }

  var body: some View {
    TextField(String(localized: .loci("projects.rename")), text: $name)
      .textFieldStyle(.roundedBorder)
      .frame(width: 180)
      .padding(10)
      .focused($focused)
      .onSubmit {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { done(trimmed) }
      }
      .onAppear { focused = true }
  }
}

/// Every project, the open one marked, the archived ones folded at the bottom; choosing an archived one opens
/// and restores it.
struct ProjectList: View {
  let bar: ProjectBar
  let home: Home
  let open: (Home) -> Void
  let start: () -> Void
  @State private var showsArchived = false
  @Environment(\.reducesMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(bar.projects, id: \.id) { project in
        row(project, dot: bar.unseen.contains(project.id))
      }
      if !bar.archived.isEmpty {
        Divider().padding(.vertical, 5).padding(.horizontal, 8)
        Button {
          withAnimation(reduceMotion ? nil : Motion.fold) { showsArchived.toggle() }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .bold))
              .rotationEffect(.degrees(showsArchived ? 90 : 0))
            Text(.loci("projects.archivedSection"))
          }
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Palette.inkMuted)
          .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
          .padding(.horizontal, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if showsArchived {
          ForEach(bar.archived, id: \.id) { project in row(project, dot: false).opacity(0.6) }
        }
      }
      Divider().padding(.vertical, 5).padding(.horizontal, 8)
      Button(action: start) {
        HStack(spacing: 10) {
          Image(systemName: "plus")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: Size.seal, height: Size.seal)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.lineStrong, lineWidth: 1.2))
          Text(.loci("projects.new"))
        }
        .foregroundStyle(Palette.inkMuted)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .font(.system(size: 13.5))
    .padding(6)
    .frame(width: 232)
  }

  private func row(_ project: Project, dot: Bool) -> some View {
    Button {
      open(.project(project.id))
    } label: {
      HStack(spacing: 10) {
        ProjectSeal(seal: project.seal, locked: !project.remembered)
        Text(verbatim: project.shownName).foregroundStyle(Palette.ink).lineLimit(1)
        Spacer(minLength: 0)
        if dot { Circle().fill(Palette.accent).frame(width: 6, height: 6) }
      }
      .padding(.horizontal, 8)
      .frame(minHeight: 34)
      .background(
        RoundedRectangle(cornerRadius: 8).fill(home == .project(project.id) ? Palette.lineStrong : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
