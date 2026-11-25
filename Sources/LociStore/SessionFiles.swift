import Foundation

/// The session files the agent CLIs keep outside the data folder. Loci reads them and never changes them.
public enum SessionFiles {
  /// The first file in `folders`, or in the folders up to `depth` levels under them, whose name `matches`.
  public static func find(in folders: [URL], depth: Int, where matches: (String) -> Bool) -> URL? {
    let files = FileManager.default
    for folder in folders {
      guard let names = try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { continue }
      if let name = names.first(where: matches) { return folder.appending(path: name) }
      guard depth > 0 else { continue }
      let below = names.sorted().map { folder.appending(path: $0, directoryHint: .isDirectory) }
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      if let found = find(in: below, depth: depth - 1, where: matches) { return found }
    }
    return nil
  }

  /// When the file last changed, so what was read of it can be kept until it changes again.
  public static func modified(_ file: URL) -> Date? {
    try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  public static func text(of file: URL) throws -> String {
    String(decoding: try Data(contentsOf: file), as: UTF8.self)
  }
}
