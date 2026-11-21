import Foundation
import LociModel

/// What the app keeps about the panels beside the files Loci writes: the order the person left the column
/// in, and when each panel was last refreshed by the app's clock.
public struct PanelState: Hashable, Codable, Sendable {
  public var order: [PanelPlace] = []
  public var refreshed: [String: Timestamp] = [:]

  public init(order: [PanelPlace] = [], refreshed: [String: Timestamp] = [:]) {
    self.order = order
    self.refreshed = refreshed
  }

  private enum CodingKeys: String, CodingKey {
    case order, refreshed
  }

  /// A file that cannot be read is an empty state: the column falls back to its first order.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    order = (try? container.decodeIfPresent([PanelPlace].self, forKey: .order)) ?? []
    refreshed = (try? container.decodeIfPresent([String: Timestamp].self, forKey: .refreshed)) ?? [:]
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
    return urls.map { url in
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
