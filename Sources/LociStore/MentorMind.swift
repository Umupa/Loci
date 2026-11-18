import Foundation
import LociModel

extension Store {
  static let memoryFolder = "memory"

  /// Where the mentor's `SOUL.md` is, whether or not it has been written.
  public func soulFile(of mentor: EntityID) throws -> URL {
    try mentorFolder(mentor).appending(path: Self.soulFile)
  }

  /// The mentor's `SOUL.md` and every text file under `memory/`, newest first. Hidden files and files that
  /// are not UTF-8 text are left out.
  public func mind(of mentor: EntityID) throws -> Mind {
    let folder = try mentorFolder(mentor)
    let soulFile = folder.appending(path: Self.soulFile)
    let soul = try? readText(soulFile)
    let memory = folder.appending(path: Self.memoryFolder)
    let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
    let files =
      FileManager.default.enumerator(at: memory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])?
      .compactMap { $0 as? URL } ?? []
    let read = files.compactMap { url -> MemoryFile? in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
        let text = try? readText(url)
      else { return nil }
      let name = url.standardizedFileURL.path(percentEncoded: false)
        .dropFirst(memory.standardizedFileURL.path(percentEncoded: false).count)
        .trimmingPrefix("/")
      return MemoryFile(
        name: String(name), text: text, modifiedAt: Timestamp(values.contentModificationDate ?? .distantPast))
    }
    return Mind(soul: soul, memory: read.sorted { $0.modifiedAt > $1.modifiedAt })
  }
}
