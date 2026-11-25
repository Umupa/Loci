import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func projectBar() async throws(HostError) -> ProjectBar {
    let projects = store.projects().filter { $0.name != nil }
    let panels = projects.map { project in
      let named = store.home(.project(project.id)).panels().compactMap(\.panel).map {
        PanelName(name: $0.name, title: $0.title)
      }
      return (project.id, named)
    }
    return ProjectBar(
      projects: projects.filter { !$0.archived }, archived: projects.filter(\.archived),
      unseen: Set(projects.filter { isUnseen($0) }.map(\.id)),
      panels: Dictionary(panels, uniquingKeysWith: { first, _ in first }))
  }

  /// A reply or a panel's refresh came after the person last opened it.
  private func isUnseen(_ project: Project) -> Bool {
    let files = store.home(.project(project.id))
    let refreshed = files.panelState().refreshed.values.max()
    let replied = try? database.latestReply(in: .project(project.id))
    guard let latest = [refreshed, replied].compactMap(\.self).max() else { return false }
    return project.seen.map { latest > $0 } ?? true
  }

  /// The project is made without a name, and the person's words are said in its conversation with what the
  /// companion is to do first. A project still without a name when that turn ends takes its first words.
  public func startProject(_ command: StartProject) async throws(HostError) -> Project {
    let text = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw .invalidRequest("say what the project is for") }
    let now = environment.now()
    let project = Project(id: environment.newID(), name: nil, seen: now, createdAt: now)
    try attempt {
      try store.saveProject(project)
      try store.home(.project(project.id)).setMemoryWritable(false)
    }
    let run = try await loci.run(of: .project(project.id))
    try await run.send(Prompt(text: text, purpose: .chat), saying: loci.context.prompts.projectStart + text)
    await follow([.projects])
    await hub.hold(
      Task {
        _ = await run.settle()
        await self.nameIfUnnamed(project.id, from: text)
      })
    return project
  }

  private func nameIfUnnamed(_ id: Project.ID, from text: String) async {
    guard let project = try? store.project(id), project.name == nil else { return }
    _ = try? store.changeProject(id) { $0.with(name: .some(Self.provisionalName(from: text))) }
    await follow([.projects])
  }

  /// The first few characters of what the person said, to a word's end when there are spaces.
  static func provisionalName(from text: String) -> String {
    let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    let words = line.split(separator: " ")
    if words.count > 1 { return words.prefix(3).joined(separator: " ") }
    return String(line.prefix(6))
  }

  public func renameProject(_ command: RenameProject) async throws(HostError) -> Project {
    let name = command.newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw .invalidRequest("a project needs a name") }
    return try await changeProject(command.project) { $0.with(name: .some(name)) }
  }

  public func describeProject(_ command: DescribeProject) async throws(HostError) -> Project {
    guard let id = command.project else { throw .invalidRequest(NameProject.outside) }
    let line = command.summary.split(whereSeparator: \.isNewline).joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
    return try await changeProject(id) { $0.with(summary: line) }
  }

  public func setProjectRemembered(_ command: SetProjectRemembered) async throws(HostError) -> Done {
    _ = try await changeProject(command.project) { $0.with(remembered: command.remembered) }
    return Done()
  }

  /// Archiving leaves everything on disk; its timers stop coming due, and its events waiting in the inbox are
  /// dropped by the worker.
  public func archiveProject(_ command: ArchiveProject) async throws(HostError) -> Done {
    _ = try await changeProject(command.project) { $0.with(archived: command.archived) }
    await follow([.timers, .loci(.panels)])
    await worker.consider()
    return Done()
  }

  public func seeProject(_ command: SeeProject) async throws(HostError) -> Done {
    _ = try await changeProject(command.project) { $0.with(seen: .some(self.environment.now())) }
    return Done()
  }

  public func pinPanel(_ command: PinPanel) async throws(HostError) -> Done {
    let files = store.home(.project(command.project))
    guard files.panel(named: command.panel)?.panel != nil else { throw .notFound(command.panel) }
    _ = try await changeProject(command.project) { project in
      let others = project.pinned.filter { $0 != command.panel }
      return project.with(pinned: command.pinned ? others + [command.panel] : others)
    }
    if !command.pinned {
      try attempt {
        _ = try store.home(.chat).changePanelState { state in
          state.order.removeAll { $0 == .pinned(command.project, command.panel) }
        }
      }
    }
    await follow([.loci(.panels)])
    return Done()
  }

  private func changeProject(_ id: Project.ID, _ change: @escaping (Project) -> Project)
    async throws(HostError) -> Project
  {
    let changed = try attempt { try store.changeProject(id, change) }
    await follow([.projects])
    return changed
  }
}

extension LocalHost {
  /// Sets the project aside with everything in it, so it leaves at once and can still come back until the
  /// next project is deleted.
  public func deleteProject(_ command: DeleteProject) async throws(HostError) -> Done {
    try await deletions.through { () async throws(HostError) in
      let id = command.project
      _ = try attempt { try store.project(id) }
      let previous = store.setAsideProjects()
      await loci.forget(.project(id))
      do throws(HostError) {
        try attempt { try store.setAsideProject(id) }
      } catch {
        await loci.forgotten(.project(id))
        throw error
      }
      await loci.forgotten(.project(id))
      await discardSetAsideProjects(previous)
      await follow([.projects, .timers, .loci(.panels), .conversation(.project(id))])
      return Done()
    }
  }

  public func restoreDeletedProject() async throws(HostError) -> Project? {
    try await deletions.through { () async throws(HostError) in
      guard let id = store.setAsideProjects().first else { return nil }
      try attempt { try store.restoreProject(id) }
      try? store.home(.project(id)).setMemoryWritable(false)
      await follow([.projects, .timers, .loci(.panels), .conversation(.project(id))])
      return try? store.project(id)
    }
  }

  /// Gets rid of projects set aside, for good: their folders, conversations, timers and what the inbox and
  /// the search still hold of them.
  func discardSetAsideProjects(_ projects: [Project.ID]? = nil) async {
    for id in projects ?? store.setAsideProjects() {
      do {
        try store.discardSetAsideProject(id)
        try database.deleteConversation(.project(id))
        try database.forgetTranscripts(of: .project(id))
        try database.forgetSources(of: id)
        try database.forgetNextUps(of: id)
        for schedule in try database.schedules() where schedule.project == id {
          try database.removeSchedule(schedule.id)
        }
        for followUp in try database.followUps() where followUp.home == .project(id) {
          _ = try database.endFollowUp(followUp.id, at: environment.now())
        }
        for event in try database.openEvents() where event.source.home == .project(id) {
          if case .waiting = event.state { try database.update(event.with(.dropped)) }
        }
      } catch {
        await hub.failed("could not discard a deleted project: \(error)")
      }
    }
  }
}
