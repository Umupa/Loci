import Foundation
import LociModel

extension LocalHost {
  public func connectors() async throws(HostError) -> Connectors {
    try await connectorKeeper.connectors()
  }

  public func connectorCalls(limit: Int) async throws(HostError) -> [ConnectorCall] {
    try attempt { try database.connectorCalls(limit: max(1, limit)) }
  }

  public func connect(_ command: Connect) async throws(HostError) -> Authorization {
    try await connectorKeeper.connect(command.connector)
  }

  public func addMCPServer(_ command: AddMCPServer) async throws(HostError) -> Authorization {
    try await connectorKeeper.add(command.address)
  }

  public func cancelConnecting(_ command: CancelConnecting) async throws(HostError) -> Done {
    await connectorKeeper.cancel(command.connector)
    return Done()
  }

  public func disconnect(_ command: Disconnect) async throws(HostError) -> Done {
    try await connectorKeeper.disconnect(command.connector)
    return Done()
  }

  public func callConnector(_ command: CallConnector, from caller: ConnectorCall.Caller?) async throws(HostError)
    -> String
  {
    guard let caller else {
      throw .invalidRequest("loci connector call works only from a conversation or a run in the background.")
    }
    return try await connectorKeeper.call(command, by: caller)
  }
}
