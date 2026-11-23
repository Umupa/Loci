import Foundation

/// One change to a panel's items. Ticking, rewording, pinning, noting, taking and moving an item are all a
/// put of the item as it is to be.
public enum PanelEdit: Hashable, Codable, Sendable {
  /// Puts the item in the section at `at`, or at its end when `at` is `nil` or past it; an item with the
  /// same id leaves where it was.
  case put(PanelItem, section: String, at: Int?)
  case remove(String)

  /// The edit that puts the panel back as it was before this one; `nil` when this one cannot be made on it.
  public func reverse(in panel: Panel) -> PanelEdit? {
    switch self {
    case .put(let item, _, _):
      guard let was = panel.place(of: item.id) else { return .remove(item.id) }
      return .put(was.item, section: was.section, at: was.index)
    case .remove(let id):
      return panel.place(of: id).map { .put($0.item, section: $0.section, at: $0.index) }
    }
  }
}

extension Panel {
  /// The panel with the edit made, or why it cannot be.
  public func applying(_ edit: PanelEdit) throws(PanelProblems) -> Panel {
    switch edit {
    case .put(let item, let target, let at):
      guard sections.contains(where: { $0.id == target }) else {
        throw PanelProblems(all: [PanelProblem("", "\(name) has no section \"\(target)\"")])
      }
      return try changingSections { section throws(PanelProblems) in
        section.items.removeAll { $0.id == item.id }
        guard section.id == target else { return }
        section.items.insert(item, at: min(max(at ?? section.items.count, 0), section.items.count))
      }
    case .remove(let id):
      guard place(of: id) != nil else {
        throw PanelProblems(all: [PanelProblem("", "\(name) has no item \"\(id)\"")])
      }
      return try changingSections { section throws(PanelProblems) in section.items.removeAll { $0.id == id } }
    }
  }
}

/// A line of a list in a panel, known by its link, or by its title when it has none, so the person's take
/// on it outlasts Loci rewriting the list.
public struct PanelLineKey: Hashable, Codable, Sendable, RawRepresentable, CodingKeyRepresentable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ line: PanelListItem) {
    rawValue = line.link?.absoluteString ?? line.title
  }
}

/// The person's take on a line of a list in a panel: kept by the app, out of Loci's reach.
public struct PanelLineMark: Hashable, Codable, Sendable {
  public var pinned: Bool
  /// 「不想再看」: the line is left out, and Loci is told not to bring it back.
  public var hidden: Bool
  public var note: String?

  public init(pinned: Bool = false, hidden: Bool = false, note: String? = nil) {
    self.pinned = pinned
    self.hidden = hidden
    self.note = note
  }

  /// A take that says nothing, so there is nothing to keep.
  public var isEmpty: Bool { !pinned && !hidden && note == nil }
}

/// Makes one edit to a panel's items, on the panel as it is in its file at that moment.
public struct EditPanel: RemoteCommand {
  public static let name = "panels.edit"
  public let panel: String
  public let edit: PanelEdit

  public init(_ panel: String, _ edit: PanelEdit) {
    self.panel = panel
    self.edit = edit
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.editPanel(self)
  }
}

/// Keeps the person's take on a line of a list in a panel; an empty take forgets it.
public struct MarkPanelLine: RemoteCommand {
  public static let name = "panels.mark"
  public let panel: String
  public let line: PanelLineKey
  public let mark: PanelLineMark

  public init(_ panel: String, _ line: PanelLineKey, _ mark: PanelLineMark) {
    self.panel = panel
    self.line = line
    self.mark = mark
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.markPanelLine(self)
  }
}
