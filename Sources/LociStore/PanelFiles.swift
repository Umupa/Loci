import Foundation
import LociModel

/// What the app keeps about the panels beside the files Loci writes: the order the person left the column
/// in, when each panel was last refreshed by the app's clock, and the person's take on lines of their lists.
public struct PanelState: Hashable, Codable, Sendable {
  public var order: [PanelPlace] = []
  public var refreshed: [String: Timestamp] = [:]
  /// By panel name, then by line.
  public var marks: [String: [PanelLineKey: PanelLineMark]] = [:]
  /// Items the person removed, by panel name, so a copy Loci saves from before cannot bring them back, even
  /// one it wrote that the person took and then removed.
  public var removals: [String: [Removal]] = [:]
  /// Panels whose refresh the person paused.
  public var paused: Set<String> = []

  /// An item the person removed, and when.
  public struct Removal: Hashable, Codable, Sendable {
    public let id: String
    public let at: Timestamp
  }

  /// How many removals a panel keeps, and for how long; Loci's copies are never older than a refresh.
  public static let removalsKept = 50
  public static let removalsLast: Int64 = 7 * 24 * 3_600_000

  public init(
    order: [PanelPlace] = [], refreshed: [String: Timestamp] = [:],
    marks: [String: [PanelLineKey: PanelLineMark]] = [:]
  ) {
    self.order = order
    self.refreshed = refreshed
    self.marks = marks
  }

  /// Remembers that the person removed the item, forgetting removals too old or too many.
  public mutating func remember(removed id: String, from panel: String, at now: Timestamp) {
    let kept = (removals[panel] ?? []).filter { $0.id != id && Self.recent($0, now: now) }
    removals[panel] = Array((kept + [Removal(id: id, at: now)]).suffix(Self.removalsKept))
  }

  /// The ids of the items the person removed from the panel lately.
  public func removed(from panel: String, now: Timestamp) -> Set<String> {
    Set((removals[panel] ?? []).filter { Self.recent($0, now: now) }.map(\.id))
  }

  private static func recent(_ removal: Removal, now: Timestamp) -> Bool {
    now.millisecondsSince1970 - removal.at.millisecondsSince1970 < removalsLast
  }

  private enum CodingKeys: String, CodingKey {
    case order, refreshed, marks, removals, paused
  }

  /// A file that cannot be read is an empty state: the column falls back to its first order.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    order = (try? container.decodeIfPresent([PanelPlace].self, forKey: .order)) ?? []
    refreshed = (try? container.decodeIfPresent([String: Timestamp].self, forKey: .refreshed)) ?? [:]
    marks = (try? container.decodeIfPresent([String: [PanelLineKey: PanelLineMark]].self, forKey: .marks)) ?? [:]
    removals = (try? container.decodeIfPresent([String: [Removal]].self, forKey: .removals)) ?? [:]
    paused = (try? container.decodeIfPresent(Set<String>.self, forKey: .paused)) ?? []
  }
}

/// `agent/panels/`: the panels Loci keeps beside the main conversation. Loci writes them with
/// `loci panel save`, and the person may edit them by hand. Beside `settings.json`, out of Loci's reach,
/// `panels.json` keeps the rest and `panels-shown/` the last copy of each panel that could be shown.
extension Store {
  static let panelsFolder = "panels"
  static let panelStateFile = "panels.json"
  static let shownPanelsFolder = "panels-shown"

  var panelsFolderURL: URL { agentFolder.appending(path: Self.panelsFolder, directoryHint: .isDirectory) }
  private var shownPanelsURL: URL { root.appending(path: Self.shownPanelsFolder, directoryHint: .isDirectory) }

  /// Every panel file, by name. A file that can be shown is copied aside; one that cannot is shown as its
  /// last copy, so a file broken by hand leaves the panel as it was, even after the app restarts. A copy
  /// whose file is gone is forgotten.
  public func panels() -> [PanelEntry] {
    let urls = files(in: panelsFolderURL, withExtension: "json")
    let names = Set(urls.map { $0.deletingPathExtension().lastPathComponent })
    for copy in files(in: shownPanelsURL, withExtension: "json")
    where !names.contains(copy.deletingPathExtension().lastPathComponent) {
      try? FileManager.default.removeItem(at: copy)
    }
    return urls.map(entry)
  }

  /// One panel file, as `panels()` reads it; `nil` when there is no such file.
  public func panel(named name: String) -> PanelEntry? {
    let url = panelFile(named: name)
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
    return entry(url)
  }

  private func entry(_ url: URL) -> PanelEntry {
    let name = url.deletingPathExtension().lastPathComponent
    let problems: [PanelProblem]
    do throws(PanelProblems) {
      let panel = try PanelCheck.read(try readPanelFile(url), name: name)
      keepShown(panel)
      return PanelEntry(name: name, panel: panel)
    } catch {
      problems = error.all
    }
    return PanelEntry(name: name, panel: shownPanel(named: name), problems: problems)
  }

  /// Writes the panel as `<name>.json`, in place of the one there.
  public func savePanel(_ panel: Panel) throws {
    try write(Formats.document(panel), to: panelFile(named: panel.name))
  }

  /// Removes the file and its copy; `notFound` when there is no such panel.
  public func removePanel(named name: String) throws {
    let url = panelFile(named: name)
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
      throw StoreError.notFound(relativePath(of: url))
    }
    try discard(url)
    try? FileManager.default.removeItem(at: shownPanelsURL.appending(path: "\(name).json"))
  }

  public func panelState() -> PanelState {
    (try? decodeJSON(PanelState.self, at: root.appending(path: Self.panelStateFile))) ?? PanelState()
  }

  @discardableResult
  public func changePanelState(_ change: (inout PanelState) -> Void) throws -> PanelState {
    var state = panelState()
    change(&state)
    try write(Formats.document(state), to: root.appending(path: Self.panelStateFile))
    return state
  }

  private func readPanelFile(_ url: URL) throws(PanelProblems) -> Data {
    do {
      return try read(url)
    } catch {
      throw PanelProblems(all: [PanelProblem("", "cannot be read: \(error)")])
    }
  }

  /// Writes the copy only when it differs, so reading the panels again and again writes nothing.
  private func keepShown(_ panel: Panel) {
    let url = shownPanelsURL.appending(path: "\(panel.name).json")
    guard let data = try? Formats.document(panel), (try? read(url)) != data else { return }
    try? write(data, to: url)
  }

  private func shownPanel(named name: String) -> Panel? {
    guard let data = try? read(shownPanelsURL.appending(path: "\(name).json")) else { return nil }
    return try? PanelCheck.read(data, name: name)
  }

  private func panelFile(named name: String) -> URL {
    panelsFolderURL.appending(path: "\(name).json")
  }
}
