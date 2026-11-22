import Foundation

public struct ReadSource: LocalToolCommand {
  public static let name = "source.read"
  public let url: URL

  public init(url: URL) { self.url = url }

  public func run(on handler: any CommandHandler) async throws(HostError) -> String {
    try await handler.readSource(url)
  }
}

public struct FetchSourceRepository: LocalToolCommand {
  public static let name = "source.repo"
  public let url: URL
  public let commit: CommitID?

  public init(url: URL, commit: CommitID? = nil) {
    self.url = url
    self.commit = commit
  }

  public func run(on handler: any CommandHandler) async throws(HostError) -> SourceCheckout {
    try await handler.fetchSourceRepository(self)
  }
}

public struct SourceCheckout: Hashable, Codable, Sendable {
  public let path: String
  public let commit: CommitID

  public init(path: String, commit: CommitID) {
    self.path = path
    self.commit = commit
  }
}

public struct ClearSourceCache: RemoteCommand {
  public static let name = "source.clear"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> Done {
    try await handler.clearSourceCache()
  }
}
