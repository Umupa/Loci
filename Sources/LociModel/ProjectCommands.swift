/// What the project bar shows: the projects in the order they were started, the archived ones apart.
public struct ProjectBar: Hashable, Codable, Sendable {
  /// Named and not archived.
  public let projects: [Project]
  public let archived: [Project]
  /// Projects with a reply or a panel's refresh the person has not opened them to see.
  public let unseen: Set<Project.ID>
  /// Each project's panels, by name and title, to pin to the chat.
  public let panels: [Project.ID: [PanelName]]

  public init(
    projects: [Project], archived: [Project] = [], unseen: Set<Project.ID> = [],
    panels: [Project.ID: [PanelName]] = [:]
  ) {
    self.projects = projects
    self.archived = archived
    self.unseen = unseen
    self.panels = panels
  }
}

/// A panel as a menu names it.
public struct PanelName: Hashable, Codable, Sendable {
  public let name: String
  public let title: String

  public init(name: String, title: String) {
    self.name = name
    self.title = title
  }
}

/// The project bar, kept current.
public struct WatchProjects: Subscription {
  public static let name = "projects"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> ProjectBar {
    try await handler.projectBar()
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .projects, .turnEnded, .everything, .loci(.panels): true
      case .source(let key): key.home != .chat
      case .item, .course, .courseActivity, .notes, .reading, .job, .media, .conversation, .review, .loci, .runtime,
        .timers, .connectors, .nextUps:
        false
      }
    }
  }
}

/// Starts a project from what the person said they want: the project is made without a name, and the words
/// are said in its conversation, where the companion names it and makes its panels.
public struct StartProject: RemoteCommand {
  public static let name = "projects.start"
  public let text: String

  public init(_ text: String) {
    self.text = text
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Project {
    try await handler.startProject(self)
  }
}

/// Renames a project, and so changes its seal. Refused for an empty name.
public struct RenameProject: RemoteCommand {
  public static let name = "projects.rename"
  public let project: Project.ID
  public let newName: String

  public init(_ project: Project.ID, to name: String) {
    self.project = project
    newName = name
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Project {
    try await handler.renameProject(self)
  }
}

/// Lets the daily review, the main conversation and `loci recall` elsewhere know of the project, or not.
public struct SetProjectRemembered: RemoteCommand {
  public static let name = "projects.remember"
  public let project: Project.ID
  public let remembered: Bool

  public init(_ project: Project.ID, remembered: Bool) {
    self.project = project
    self.remembered = remembered
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.setProjectRemembered(self)
  }
}

/// Folds a project out of the bar and pauses its timers, keeping everything; or brings it back.
public struct ArchiveProject: RemoteCommand {
  public static let name = "projects.archive"
  public let project: Project.ID
  public let archived: Bool

  public init(_ project: Project.ID, archived: Bool) {
    self.project = project
    self.archived = archived
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.archiveProject(self)
  }
}

/// Takes a project out with its conversation, panels, timers and memory. It can be brought back with
/// `RestoreDeletedProject` until the next project is deleted, or until the app quits.
public struct DeleteProject: RemoteCommand {
  public static let name = "projects.delete"
  public let project: Project.ID

  public init(_ project: Project.ID) {
    self.project = project
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.deleteProject(self)
  }
}

/// Brings back the project the last `DeleteProject` took out; `nil` when that can no longer be undone.
public struct RestoreDeletedProject: RemoteCommand {
  public static let name = "projects.restoreDeleted"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Project? {
    try await handler.restoreDeletedProject()
  }
}

/// The person opened the project: what was new in it is seen.
public struct SeeProject: RemoteCommand {
  public static let name = "projects.see"
  public let project: Project.ID

  public init(_ project: Project.ID) {
    self.project = project
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.seeProject(self)
  }
}

/// Shows a project's panel in the chat's column too, or stops showing it there. Refused for a panel of the
/// chat.
public struct PinPanel: RemoteCommand {
  public static let name = "projects.pinPanel"
  public let project: Project.ID
  public let panel: String
  public let pinned: Bool

  public init(_ panel: String, of project: Project.ID, pinned: Bool) {
    self.project = project
    self.panel = panel
    self.pinned = pinned
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.pinPanel(self)
  }
}

/// `loci project name`: names the project the session is in. The app fills the project in from the session.
public struct NameProject: LocalToolCommand {
  public static let name = "projects.name"
  public let newName: String
  public let project: Project.ID?

  public init(_ name: String, of project: Project.ID? = nil) {
    newName = name
    self.project = project
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Project {
    guard let project else { throw .invalidRequest(Self.outside) }
    return try await handler.renameProject(RenameProject(project, to: newName))
  }

  public static let outside = "this session is in no project; `loci project` works only inside one"
}

/// `loci project describe`: says in a line what the project the session is in is doing, all the main
/// conversation knows of it.
public struct DescribeProject: LocalToolCommand {
  public static let name = "projects.describe"
  public let summary: String
  public let project: Project.ID?

  public init(_ summary: String, of project: Project.ID? = nil) {
    self.summary = summary
    self.project = project
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Project {
    try await handler.describeProject(self)
  }
}
