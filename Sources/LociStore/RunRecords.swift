import Foundation
import LociModel

/// `agent/runs/<day>/<id>.md`: what a run in the background did, for the companion to read later. Only the
/// app writes these.
extension Store {
  static let runsFolder = "runs"

  /// Where the record of a run started on `day` is, relative to `agent/`.
  public static func runRecordPath(of run: Run.ID, on day: Day) -> String {
    "\(runsFolder)/\(day)/\(run).md"
  }

  public func saveRunRecord(_ text: String, at path: String) throws {
    try write(Data(text.utf8), to: try runRecordURL(path))
  }

  /// `nil` when there is none at `path`.
  public func runRecord(at path: String) throws -> String? {
    try optionalText(at: try runRecordURL(path))
  }

  private func runRecordURL(_ path: String) throws -> URL {
    let parts = path.split(separator: "/").map(String.init)
    guard parts.count == 3, parts[0] == Self.runsFolder, Day(parts[1]) != nil else {
      throw StoreError.invalid(FileProblem(path: path, kind: .invalid, reason: "not a run record"))
    }
    return agentFolder.appending(path: parts[0]).appending(path: parts[1])
      .appending(path: try Self.plainName(parts[2]))
  }
}
