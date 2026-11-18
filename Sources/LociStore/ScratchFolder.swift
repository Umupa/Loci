import Foundation

/// An empty folder of its own in the system's temporary folder, for an agent that should see nothing but
/// what it is told. Removed when no longer needed.
public struct ScratchFolder: Sendable {
  public let url: URL

  public init() throws {
    url = FileManager.default.temporaryDirectory.appending(path: "loci-scratch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  public func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}
