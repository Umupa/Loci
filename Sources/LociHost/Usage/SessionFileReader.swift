import Foundation
import LociAgents
import LociModel
import LociStore

/// Finds and reads the CLIs' session files, keeping what it read of each until the file changes, so the
/// usage page opens again at once.
actor SessionFileReader {
  private let folders: SessionFolders
  private let timeZone: TimeZone
  private var places: [String: URL] = [:]
  private var read: [URL: (modified: Date, parsed: SessionFile?)] = [:]

  init(folders: SessionFolders, timeZone: TimeZone) {
    self.folders = folders
    self.timeZone = timeZone
  }

  /// What the session's file says; `nil` when its CLI keeps no file Loci reads or the file is gone.
  func file(of session: SessionRecord) -> SessionFile? {
    guard let handle = session.handle, let file = place(of: session, handle: handle),
      let modified = SessionFiles.modified(file)
    else { return nil }
    if let kept = read[file], kept.modified == modified { return kept.parsed }
    let parsed = (try? SessionFiles.text(of: file)).flatMap {
      SessionFolders.sessionFile(of: session.runtime.provider, text: $0)
    }
    read[file] = (modified, parsed)
    return parsed
  }

  private func place(of session: SessionRecord, handle: String) -> URL? {
    let key = "\(session.runtime.provider.rawValue)/\(handle)"
    if let known = places[key] { return known }
    guard
      let search = folders.search(
        provider: session.runtime.provider, handle: handle, startedAt: session.startedAt, timeZone: timeZone),
      let file = SessionFiles.find(in: search.folders, depth: search.depth, where: search.name.matches)
    else { return nil }
    places[key] = file
    return file
  }
}
