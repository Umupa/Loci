import Foundation
import LociModel

/// `runs/<day>/<id>.md` in the run's home: what a run in the background did, for the companion to read later. Only the
/// app writes these.
extension Store {
  static let runsFolder = "runs"

  public func saveRunRecord(_ text: String, at path: String) throws {
    try write(Data(text.utf8), to: try runRecordURL(path))
  }

  /// `nil` when there is none at `path`.
  public func runRecord(at path: String) throws -> String? {
    try optionalText(at: try runRecordURL(path))
  }

  private func runRecordURL(_ path: String) throws -> URL {
    guard let url = try dayFile(at: path, under: [Self.runsFolder]) else {
      throw StoreError.invalid(FileProblem(path: path, kind: .invalid, reason: "not a run record"))
    }
    return url
  }

  /// `<folder>/<day>/<file>` under `agent/` or under a project's folder there; `nil` for any other path.
  func dayFile(at path: String, under folders: [String]) throws -> URL? {
    var parts = path.split(separator: "/").map(String.init)
    var base = agentFolder
    if parts.count == 5, parts[0] == Self.projectsFolder, let project = EntityID(canonical: parts[1]) {
      base = home(.project(project)).folder
      parts.removeFirst(2)
    }
    guard parts.count == 3, folders.contains(parts[0]), Day(parts[1]) != nil else { return nil }
    return base.appending(path: parts[0]).appending(path: parts[1]).appending(path: try Self.plainName(parts[2]))
  }
}
