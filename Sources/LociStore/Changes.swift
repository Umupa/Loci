import Foundation
import LociModel

extension Store {
  /// Changes made to the folder by anyone, this process included, in batches.
  ///
  /// Watching starts when this is called and stops when the stream is dropped or its task is cancelled.
  public func changes() -> AsyncStream<Set<ContentChange>> {
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let resolvedRoot = Self.resolved(root)
    let events = FileEvents.stream(under: resolvedRoot)
    let store = self
    let (changes, continuation) = AsyncStream.makeStream(of: Set<ContentChange>.self)
    let task = Task {
      var map = ChangeMap(folders: store.knownFolders())
      for await event in events {
        let found: Set<ContentChange>
        switch event {
        case .rescan:
          found = [.everything]
        case .changed(let paths):
          let prefix = resolvedRoot + "/"
          let relative = paths.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
          found = map.changes(at: relative) { store.id(ofFolder: store.root.appending(path: $0)) }
        }
        if !found.isEmpty { continuation.yield(found) }
      }
      continuation.finish()
    }
    continuation.onTermination = { _ in task.cancel() }
    return changes
  }

  private func knownFolders() -> [String: EntityID] {
    var known: [String: EntityID] = [:]
    for folder in subfolders(of: libraryFolder) {
      known["library/\(folder.lastPathComponent)"] = id(ofFolder: folder)
    }
    return known
  }

  private static func resolved(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}
