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

  /// A reply, a panel's refresh, or new numbers in a chart of its panels came after the person last opened it.
  private func isUnseen(_ project: Project) -> Bool {
    let home = Home.project(project.id)
    let files = store.home(home)
    let panels = files.panels().compactMap(\.panel)
    let refreshed = files.panelState().refreshed.values.max()
    let replied = try? database.latestReply(in: home.conversation)
    let charted = ((try? database.sourceSnapshots(Set(panels.flatMap { $0.sources(of: home) }))) ?? [:])
      .values.map(\.fetched).max()
    guard let latest = [refreshed, replied, charted].compactMap(\.self).max() else { return false }
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

  /// Named in the same edit that finds it unnamed, so a name the companion gave meanwhile always stays.
  private func nameIfUnnamed(_ id: Project.ID, from text: String) async {
    let name = Self.provisionalName(from: text)
    _ = try? await changeProject(id) { $0.name == nil ? $0.with(name: .some(name)) : $0 }
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

  /// Kept out of memory, the project's review under way stops and its reviews wait until it is remembered again;
  /// the rest of its work goes on.
  public func setProjectRemembered(_ command: SetProjectRemembered) async throws(HostError) -> Done {
    _ = try await changeProject(command.project) { $0.with(remembered: command.remembered) }
    if command.remembered {
      await worker.consider()
    } else {
      await worker.reviewStopped(in: .project(command.project))
    }
    return Done()
  }

  /// Archiving leaves everything on disk; its timers stop coming due, the run under way there stops, and its
  /// events wait in the inbox until it is opened again.
  public func archiveProject(_ command: ArchiveProject) async throws(HostError) -> Done {
    try await loci.context.steadily { () async throws(HostError) in
      _ = try await changeProject(command.project) { $0.with(archived: command.archived) }
      if command.archived { await close(command.project) } else { await loci.context.life.moved(command.project) }
    }
    await follow([.timers, .loci(.panels), .nextUps])
    await worker.consider()
    return Done()
  }

  /// Whatever began in the project may no longer write there, and the run under way there stops.
  func close(_ project: Project.ID) async {
    await loci.context.life.moved(project)
    await worker.homeClosed(.project(project))
  }

  /// Opening a project with nothing new in it changes nothing, so no one watching projects looks again.
  public func seeProject(_ command: SeeProject) async throws(HostError) -> Done {
    if let project = store.projects().first(where: { $0.id == command.project }), !isUnseen(project) { return Done() }
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

  private func changeProject(_ id: Project.ID, _ change: @escaping @Sendable (Project) -> Project)
    async throws(HostError) -> Project
  {
    let changed = try await loci.context.changeProject(id, change)
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
      let life = loci.context.life
      await loci.context.steadily {
        await life.leave(id)
        await worker.homeClosed(.project(id))
      }
      await worker.quiet(.project(id))
      await loci.forget(.project(id))
      do throws(HostError) {
        try await loci.context.steadily { () throws(HostError) in try attempt { try store.setAsideProject(id) } }
      } catch {
        await life.stayed(id)
        await loci.forgotten(.project(id))
        throw error
      }
      await life.stayed(id)
      await loci.forgotten(.project(id))
      await discardSetAsideProjects(previous)
      await follow([.projects, .timers, .loci(.panels), .conversation(.project(id))])
      return Done()
    }
  }

  public func restoreDeletedProject() async throws(HostError) -> Project? {
    try await deletions.through { () async throws(HostError) in
      guard let id = store.setAsideProjects().first else { return nil }
      try await loci.context.steadily { () async throws(HostError) in
        try attempt { try store.restoreProject(id) }
        await loci.context.life.moved(id)
      }
      try? store.home(.project(id)).setMemoryWritable(false)
      await follow([.projects, .timers, .loci(.panels), .conversation(.project(id))])
      return try? store.project(id)
    }
  }

  /// Gets rid of projects set aside, for good, once their run under way has stopped: first everything the
  /// database keeps of them in one write, then their folders. Until both are done the project stays set aside,
  /// so the next deletion tries again.
  func discardSetAsideProjects(_ projects: [Project.ID]? = nil) async {
    for id in projects ?? store.setAsideProjects() {
      await worker.quiet(.project(id))
      do {
        try await loci.context.steadily { () throws in
          try database.forgetProject(id)
          try store.discardSetAsideProject(id)
        }
      } catch {
        await hub.failed("could not discard a deleted project: \(error)")
      }
    }
  }
}
