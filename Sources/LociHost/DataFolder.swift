import Foundation

/// Where Loci keeps its data, and the one place it must never use.
public enum DataFolder: Equatable, Sendable {
  case use(root: URL)
  /// The folder belongs to the older Loci and its format is incompatible.
  case refuse(path: String)

  public static let name = "Loci-Beta"
  public static let olderAppName = "Loci"
  public static let databaseName = "loci.sqlite"

  /// `LOCI_ROOT` when it is set (a leading `~` means `home`), otherwise `~/Loci-Beta`. The older app's
  /// `~/Loci` is refused however it is spelled.
  public static func choose(environment: [String: String], home: URL) -> DataFolder {
    let root: URL
    if let given = environment["LOCI_ROOT"], !given.isEmpty {
      root = given.hasPrefix("~/") ? home.appending(path: String(given.dropFirst(2))) : URL(filePath: given)
    } else {
      root = home.appending(path: name)
    }
    let older = home.appending(path: olderAppName)
    guard canonical(root) != canonical(older) else { return .refuse(path: canonical(root)) }
    return .use(root: root)
  }

  public static func database(in root: URL) -> URL {
    root.appending(path: databaseName)
  }

  private static func canonical(_ url: URL) -> String {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
