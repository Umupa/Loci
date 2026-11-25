/// Where a slot sits in the panel column, without what it shows: what moving and remembering the order use.
public enum PanelPlace: Hashable, Codable, Sendable {
  /// 「接着读」.
  case reading
  case panel(String)
  /// A project's panel pinned to the chat's column.
  case pinned(Project.ID, String)
}

extension PanelSlot {
  public var place: PanelPlace {
    switch self {
    case .reading: .reading
    case .panel(let panel): .panel(panel.name)
    case .pinned(let project, let panel): .pinned(project, panel.name)
    }
  }
}

/// A panel's file as Loci sees it with `loci panel`: what it shows, and what is wrong with the file now.
public struct PanelEntry: Hashable, Codable, Sendable {
  public let name: String
  /// The panel as it last could be shown; `nil` when the file never could be.
  public let panel: Panel?
  /// Empty when the file can be shown as it is.
  public let problems: [PanelProblem]

  public init(name: String, panel: Panel?, problems: [PanelProblem] = []) {
    self.name = name
    self.panel = panel
    self.problems = problems
  }
}

/// The panel column beside a home's conversation. The chat's also shows the panels projects pinned to it.
/// Every command on panels carries its project; one without, as an older Mac sends it, is the chat's.
public struct WatchPanelColumn: Subscription {
  public static let name = "panels"
  public let project: Project.ID?

  public init(of home: Home = .chat) {
    project = home.project
  }

  public var home: Home { Home(project) }

  public func value(from handler: any CommandHandler) async throws(HostError) -> PanelColumn {
    try await handler.panelColumn(of: home)
  }

  /// 「接着读」 lists items read partway, by their titles.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .loci(let file): file == .panels
      case .reading, .item, .everything, .projects, .source: true
      case .course, .courseActivity, .notes, .job, .media, .conversation, .turnEnded, .review, .runtime, .timers,
        .connectors, .nextUps:
        false
      }
    }
  }
}

/// Refreshes a panel in the background as soon as no other panel is being refreshed.
public struct RefreshPanel: RemoteCommand {
  public static let name = "panels.refresh"
  public let panel: String
  public let project: Project.ID?

  public init(_ panel: PanelRef) {
    self.panel = panel.name
    project = panel.home.project
  }

  public var ref: PanelRef { PanelRef(panel, in: Home(project)) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.refreshPanel(self)
  }
}

/// Puts a slot at the top of a home's column; the rest keep their order.
public struct MovePanelToTop: RemoteCommand {
  public static let name = "panels.moveToTop"
  public let place: PanelPlace
  public let project: Project.ID?

  public init(_ place: PanelPlace, in home: Home) {
    self.place = place
    project = home.project
  }

  public init(_ slot: PanelSlot, in home: Home) {
    self.init(slot.place, in: home)
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.movePanelToTop(self)
  }
}

/// Deletes the panel's file. 「接着读」 cannot be removed.
public struct RemovePanel: RemoteCommand {
  public static let name = "panels.remove"
  public let panel: String
  public let project: Project.ID?

  public init(_ panel: PanelRef) {
    self.panel = panel.name
    project = panel.home.project
  }

  public var ref: PanelRef { PanelRef(panel, in: Home(project)) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.removePanel(self)
  }
}

/// Writes `panels/<name>.json` in the home's folder, refused with every `PanelProblem` when the panel cannot
/// be shown. A new panel goes to the bottom of the column.
public struct SavePanel: RemoteCommand {
  public static let name = "panels.save"
  public let panel: Panel
  public let project: Project.ID?

  public init(_ panel: Panel, in home: Home = .chat) {
    self.panel = panel
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.savePanel(self)
  }
}

/// Every panel file of a home, by name, broken ones too.
public struct ListPanels: RemoteCommand {
  public static let name = "panels.list"
  public let project: Project.ID?

  public init(of home: Home = .chat) {
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [PanelEntry] {
    try await handler.panels(of: home)
  }
}
