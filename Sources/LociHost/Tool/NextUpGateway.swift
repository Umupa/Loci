import Foundation
import LociModel

/// `loci next`: the cards and conditions land in the home of the session the command came from.
extension ToolGateway {
  static func runNextUp(_ name: String, _ body: Data, in home: Home, on host: LocalHost)
    async throws(HostError) -> Data?
  {
    switch name {
    case AddNextUp.name:
      let command = try WireCodec.decode(AddNextUp.self, from: body)
      return try WireCodec.encode(
        try await host.addNextUp(AddNextUp(command.what, asking: command.question, key: command.key, in: home)))
    case ProposeApproval.name:
      let command = try WireCodec.decode(ProposeApproval.self, from: body)
      return try WireCodec.encode(
        try await host.proposeApproval(ProposeApproval(command.approval, why: command.why, in: home)))
    case AddNextUpCondition.name:
      let command = try WireCodec.decode(AddNextUpCondition.self, from: body)
      return try WireCodec.encode(
        try await host.addNextUpCondition(
          AddNextUpCondition(
            command.field, command.comparison, command.threshold, say: command.say, asking: command.question,
            in: home)))
    case ListNextUpConditions.name:
      return try WireCodec.encode(try await host.nextUpConditions(of: home))
    case RemoveNextUpCondition.name:
      let command = try WireCodec.decode(RemoveNextUpCondition.self, from: body)
      guard try await host.nextUpConditions(of: home).contains(where: { $0.id == command.condition }) else {
        throw .notFound("condition \(command.condition)")
      }
      return try WireCodec.encode(try await host.removeNextUpCondition(command))
    default:
      return nil
    }
  }
}
