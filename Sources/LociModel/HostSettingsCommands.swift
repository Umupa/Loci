import Foundation

/// Where the host keeps its files, to show. Revealing the folder goes through `Host.localFile`.
public struct DataLocation: RemoteCommand {
  public static let name = "settings.dataLocation"

  public init() {}

  public func run(on handler: any CommandHandler) async throws(HostError) -> HostPath {
    await handler.dataLocation()
  }
}
