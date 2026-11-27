import LociModel
import SwiftUI

/// Every project, the chat above them, the open one marked, the archived ones folded at the bottom; choosing an
/// archived one opens and restores it.
struct ProjectList: View {
  let bar: ProjectBar
  let home: Home
  var actions: ProjectBarActions?
  let open: (Home) -> Void
  let start: () -> Void
  @State private var showsArchived = false
  @State private var renaming: Project.ID?
  @State private var reiconing: Project.ID?
  @Environment(\.reducesMotion) private var reduceMotion
  @Environment(\.changesAllowed) private var changesAllowed

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      chatRow
      Divider().padding(.vertical, 5).padding(.horizontal, 8)
      ViewThatFits(in: .vertical) {
        projects
        ScrollView { projects }
          .scrollIndicators(.never)
          .frame(maxHeight: 360)
      }
      Divider().padding(.vertical, 5).padding(.horizontal, 8)
      newRow
    }
    .font(.system(size: 13.5))
    .padding(6)
    .frame(width: 232)
  }

  private var chatRow: some View {
    let selected = home == .chat
    return ListRow(selected: selected) {
      open(.chat)
    } label: {
      Image(systemName: Symbols.ask)
        .font(.system(size: 13.5, weight: .medium))
        .foregroundStyle(selected ? Palette.sidebarSelectedInk : Palette.inkMuted)
        .frame(width: Size.seal, height: Size.seal)
      Text(.loci("projects.chat"))
        .foregroundStyle(Palette.ink)
        .fontWeight(selected ? .medium : .regular)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }

  private var projects: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(bar.projects, id: \.id) { project in
        projectRow(project, dot: bar.unseen.contains(project.id))
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
          ForEach(bar.archived, id: \.id) { project in
            projectRow(project, dot: false, archived: true).opacity(0.6)
          }
        }
      }
    }
  }

  private var newRow: some View {
    ListRow(selected: false, action: start) {
      ProjectSeal(symbol: "", size: Size.seal, ghost: true)
        .overlay {
          Image(systemName: Symbols.add)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.inkMuted)
        }
      Text(.loci("projects.new")).foregroundStyle(Palette.inkMuted)
      Spacer(minLength: 0)
    }
    .disabled(!changesAllowed)
  }

  private func projectRow(_ project: Project, dot: Bool, archived: Bool = false) -> some View {
    let selected = home == .project(project.id)
    return ListRow(selected: selected) {
      open(.project(project.id))
    } label: {
      ProjectSeal(symbol: project.symbol, selected: selected, locked: !project.remembered)
      Text(verbatim: project.shownName)
        .foregroundStyle(Palette.ink)
        .fontWeight(selected ? .medium : .regular)
        .lineLimit(1)
      Spacer(minLength: 0)
      if dot { Circle().fill(Palette.accent).frame(width: 6, height: 6) }
    }
    .help(Text(verbatim: project.summary.isEmpty ? project.shownName : project.summary))
    .contextMenu {
      if changesAllowed, !archived, let actions {
        ProjectMenuItems(bar: bar, project: project, actions: actions) {
          renaming = project.id
        } reicon: {
          reiconing = project.id
        }
      }
    }
    .popover(
      isPresented: Binding(get: { renaming == project.id }, set: { if !$0 { renaming = nil } }), arrowEdge: .trailing
    ) {
      if let actions {
        RenameField(name: project.shownName) { name in
          renaming = nil
          actions.rename(project.id, name)
        }
      }
    }
    .popover(
      isPresented: Binding(get: { reiconing == project.id }, set: { if !$0 { reiconing = nil } }), arrowEdge: .trailing
    ) {
      if let actions {
        ProjectIconPicker(selected: project.symbol) { icon in
          reiconing = nil
          actions.reicon(project.id, icon)
        }
      }
    }
  }
}

/// One row of the project list, washed in amber when selected and gray under the pointer.
private struct ListRow<Content: View>: View {
  let selected: Bool
  let action: () -> Void
  @ViewBuilder let label: Content
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) { label }
        .padding(.horizontal, 8)
        .frame(minHeight: 34)
        .background(
          RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            .fill(selected ? Palette.tint : hovering ? Palette.fill : Color.clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Context menu items shared by project tabs in the bar and rows in the list.
struct ProjectMenuItems: View {
  let bar: ProjectBar
  let project: Project
  let actions: ProjectBarActions
  let rename: () -> Void
  let reicon: () -> Void

  var body: some View {
    Button(.loci("projects.rename"), systemImage: Symbols.pencil, action: rename)
    Button(.loci("projects.changeIcon"), systemImage: "square.grid.2x2", action: reicon)
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
    Button(.loci("projects.delete"), systemImage: Symbols.delete, role: .destructive) { actions.delete(project.id) }
  }
}

/// A project's new name, typed where its seal is.
struct RenameField: View {
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
