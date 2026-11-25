import LociModel
import SwiftUI

/// The companion's page: the project bar over the chat or the project it has open, or over the field a new
/// project starts from. The open one is remembered for the Mac.
struct CompanionPage: View {
  @Environment(\.host) private var host
  @Environment(\.reducesMotion) private var reduceMotion
  let focusRequest: Int
  let attach: () -> Void
  let opened: (WindowState) -> Void
  let failed: (HostError) -> Void
  @Binding var columnPreferred: Bool
  let memory: WindowMemory
  @State private var project: Project.ID?
  @State private var recalled = false
  @State private var bar: Feed<ProjectBar>?
  @State private var starting: Starting?
  @State private var notice: Notice?

  /// A project being started: the words, once sent, and the project they started.
  struct Starting: Equatable {
    var sent: String?
    var project: Project.ID?
  }

  /// What the last archiving or deletion took away, to undo.
  enum Notice: Equatable {
    case archived(Project.ID, serial: UUID = UUID())
    case deleted(serial: UUID = UUID())
  }

  private var home: Home { project.map(Home.project) ?? .chat }
  private var shownBar: ProjectBar { bar?.value ?? ProjectBar(projects: []) }

  var body: some View {
    ZStack(alignment: .top) {
      Group {
        if let starting {
          NewProjectStage(sent: starting.sent, send: start)
            .padding(.top, Size.projectBarRoom)
            .padding(.horizontal, Spacing.m)
        } else {
          TalkScreen(
            home: home, pinned: Set(openProject?.pinned ?? []), focusRequest: focusRequest, attach: attach,
            opened: opened, failed: failed, columnPreferred: $columnPreferred
          )
          .id(home)
          .transition(.opacity)
          .environment(\.projectName, openProject?.name)
        }
      }
      ProjectBarView(bar: shownBar, home: home, starting: starting != nil, actions: actions)
        .padding(.top, 11)
    }
    .overlay(alignment: .bottom) {
      if let notice {
        DeletedNotice(words: words(of: notice)) { undo(notice) }
          .changesData()
          .padding(.bottom, 84)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? nil : Motion.standard, value: notice)
    .animation(reduceMotion ? nil : Motion.standard, value: starting == nil)
    .subscribing(WatchProjects(), into: $bar)
    .onAppear {
      guard !recalled else { return }
      recalled = true
      project = memory.recallProject()
    }
    .onChange(of: project) { memory.rememberProject(project) }
    .onChange(of: bar?.value) { settle() }
    .task(id: notice) {
      guard let shown = notice else { return }
      try? await Task.sleep(for: .seconds(6))
      if !Task.isCancelled, notice == shown { notice = nil }
    }
  }

  private var openProject: Project? {
    guard let project else { return nil }
    return (shownBar.projects + shownBar.archived).first { $0.id == project }
  }

  /// A started project is done once it has its name; a project gone elsewhere leaves the chat open; what the
  /// open project says new is seen.
  private func settle() {
    guard let value = bar?.value else { return }
    if let id = starting?.project, value.projects.contains(where: { $0.id == id }) {
      starting = nil
      project = id
    }
    if let project, !(value.projects + value.archived).contains(where: { $0.id == project }) { self.project = nil }
    if let project, value.unseen.contains(project) { send(SeeProject(project)) }
  }

  private var actions: ProjectBarActions {
    ProjectBarActions(
      open: { chosen in
        starting = nil
        if case .project(let id) = chosen, shownBar.archived.contains(where: { $0.id == id }) {
          send(ArchiveProject(id, archived: false))
        }
        withAnimation(reduceMotion ? nil : Motion.standard) { project = chosen.project }
        if let id = chosen.project { send(SeeProject(id)) }
      },
      start: { starting = Starting() },
      rename: { id, name in send(RenameProject(id, to: name)) },
      pin: { id, panel, pinned in send(PinPanel(panel, of: id, pinned: pinned)) },
      remember: { id, remembered in send(SetProjectRemembered(id, remembered: remembered)) },
      archive: { id in
        if project == id { project = nil }
        send(ArchiveProject(id, archived: true))
        notice = .archived(id)
      },
      delete: { id in
        if project == id { project = nil }
        send(DeleteProject(id))
        notice = .deleted()
      })
  }

  private func start(_ words: String) {
    starting?.sent = words
    Task {
      do throws(HostError) {
        starting?.project = try await host.run(StartProject(words)).id
        settle()
      } catch {
        starting = nil
        failed(error)
      }
    }
  }

  private func words(of notice: Notice) -> LocalizedStringResource {
    switch notice {
    case .archived: .loci("projects.archived")
    case .deleted: .loci("projects.deleted")
    }
  }

  private func undo(_ notice: Notice) {
    self.notice = nil
    switch notice {
    case .archived(let id, _): send(ArchiveProject(id, archived: false))
    case .deleted: send(RestoreDeletedProject())
    }
  }

  private func send<C: Command>(_ command: C) {
    Task {
      do throws(HostError) {
        _ = try await host.run(command)
      } catch {
        failed(error)
      }
    }
  }
}
