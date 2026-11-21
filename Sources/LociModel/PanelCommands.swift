/// Where a slot sits in the panel column, without what it shows: what moving and remembering the order use.
public enum PanelPlace: Hashable, Codable, Sendable {
  /// 「接着读」.
  case reading
  case panel(String)
}

extension PanelSlot {
  public var place: PanelPlace {
    switch self {
    case .reading: .reading
    case .panel(let panel): .panel(panel.name)
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

/// The panel column beside the main conversation.
public struct WatchPanelColumn: Subscription {
  public static let name = "panels"

  public init() {}

  public func value(from handler: any CommandHandler) async throws(HostError) -> PanelColumn {
    try await handler.panelColumn()
  }

  /// 「接着读」 lists items read partway, by their titles.
  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .loci(let file): file == .panels
      case .reading, .item, .everything: true
      case .notes, .job, .media, .conversation, .turnEnded, .review, .events, .runtime: false
      }
    }
  }
}

/// Refreshes a panel in the background as soon as no other panel is being refreshed.
public struct RefreshPanel: Command {
  public static let name = "panels.refresh"
  public let panel: String

  public init(_ panel: String) {
    self.panel = panel
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.refreshPanel(self)
  }
}

/// Puts a slot at the top of the column; the rest keep their order.
public struct MovePanelToTop: Command {
  public static let name = "panels.moveToTop"
  public let place: PanelPlace

  public init(_ place: PanelPlace) {
    self.place = place
  }

  public init(_ slot: PanelSlot) {
    place = slot.place
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.movePanelToTop(self)
  }
}

/// Deletes the panel's file. 「接着读」 cannot be removed.
public struct RemovePanel: Command {
  public static let name = "panels.remove"
  public let panel: String

  public init(_ panel: String) {
    self.panel = panel
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.removePanel(self)
  }
}

/// Writes `agent/panels/<name>.json`, refused with every `PanelProblem` when the panel cannot be shown. A
/// new panel goes to the bottom of the column.
public struct SavePanel: Command {
  public static let name = "panels.save"
  public let panel: Panel

  public init(_ panel: Panel) {
    self.panel = panel
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.savePanel(self)
  }
}

/// Every panel file, by name, broken ones too.
public struct ListPanels: Command {
  public static let name = "panels.list"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> [PanelEntry] {
    try await handler.panels()
  }
}
