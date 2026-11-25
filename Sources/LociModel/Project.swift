import Foundation

/// One long-running thing the person does with the companion: its own conversation, panels, timers and
/// memory, under `agent/projects/<id>/`. What only the app changes is kept in `projects/<id>/project.json`.
public struct Project: Hashable, Codable, Sendable, Identifiable {
  public typealias ID = EntityID
  public let id: ID
  /// `nil` while the companion is still starting it; the project bar leaves it out until it has one.
  public let name: String?
  /// What the project is doing, in a line: all the main conversation knows of it.
  public let summary: String
  /// Whether the daily review, the main conversation and `loci recall` elsewhere may know of it.
  public let remembered: Bool
  public let archived: Bool
  /// The project's panels shown in the chat's column too, by name.
  public let pinned: [String]
  /// When the person last had it open; `nil` before they ever did.
  public let seen: Timestamp?
  public let createdAt: Timestamp

  public init(
    id: ID, name: String?, summary: String = "", remembered: Bool = true, archived: Bool = false,
    pinned: [String] = [], seen: Timestamp? = nil, createdAt: Timestamp
  ) {
    self.id = id
    self.name = name
    self.summary = summary
    self.remembered = remembered
    self.archived = archived
    self.pinned = pinned
    self.seen = seen
    self.createdAt = createdAt
  }

  /// The character on its seal: the first of its name, upper case.
  public var seal: String {
    guard let first = name?.first(where: { !$0.isWhitespace }) else { return "" }
    return String(first).uppercased()
  }

  public func with(
    name: String?? = nil, summary: String? = nil, remembered: Bool? = nil, archived: Bool? = nil,
    pinned: [String]? = nil, seen: Timestamp?? = nil
  ) -> Project {
    Project(
      id: id, name: name ?? self.name, summary: summary ?? self.summary, remembered: remembered ?? self.remembered,
      archived: archived ?? self.archived, pinned: pinned ?? self.pinned, seen: seen ?? self.seen,
      createdAt: createdAt)
  }
}

/// Where something belongs: the chat, or one project. Conversations, panels, timers, notes and memory are
/// each kept under one.
public enum Home: Hashable, Codable, Sendable {
  case chat
  case project(Project.ID)

  public init(_ project: Project.ID?) {
    self = project.map(Home.project) ?? .chat
  }

  /// The project, or `nil` for the chat; how commands and events carry a home on the wire, so a Mac that
  /// knows no projects reads them as the chat's.
  public var project: Project.ID? {
    if case .project(let id) = self { id } else { nil }
  }

  /// The conversation of the home.
  public var conversation: ConversationRef {
    switch self {
    case .chat: .main
    case .project(let id): .project(id)
    }
  }

  /// `projects/<id>/` for a project, nothing for the chat: where its files are under `agent/`.
  public var folder: String {
    project.map { "projects/\($0)/" } ?? ""
  }
}

/// A panel, by the home it belongs to and its name there.
public struct PanelRef: Hashable, Codable, Sendable {
  public let home: Home
  public let name: String

  public init(_ name: String, in home: Home = .chat) {
    self.home = home
    self.name = name
  }

  /// The panel's name for a chat panel, `projects/<id>/<name>` for a project's: unique among every panel.
  public var key: String { home.folder + name }
}
