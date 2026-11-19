import Foundation

/// The `loci` command the app gives its agents, and the socket it reaches the app through.
public struct AgentTool: Hashable, Sendable {
  /// The folder the `loci` program is in.
  public let folder: URL
  public let socket: URL

  public init(folder: URL, socket: URL) {
    self.folder = folder
    self.socket = socket
  }
}
