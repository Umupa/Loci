import Foundation
import LociModel

/// `loci next`: the cards land in the home of the session the command came from. A card a run puts up keeps
/// its event's deadline unless it gives an earlier one, and a watch finding's card takes the finding's key.
extension ToolGateway {
  static func runNextUp(_ name: String, _ body: Data, in home: Home, from event: Event?, on host: LocalHost)
    async throws(HostError) -> Data?
  {
    let now = host.environment.now()
    switch name {
    case AddNextUp.name:
      let command = try WireCodec.decode(AddNextUp.self, from: body)
      let deadline = try Event.deadline(command.deadline, under: event, after: now)
      let finding: WatchFinding? = if case .watch(let finding, _)? = event?.source { finding } else { nil }
      return try WireCodec.encode(
        try await host.addNextUp(
          AddNextUp(
            command.what, asking: command.question, key: finding?.key ?? command.key, in: home, deadline: deadline),
          fromWatch: finding != nil))
    case ProposeApproval.name:
      let command = try WireCodec.decode(ProposeApproval.self, from: body)
      let deadline = try Event.deadline(command.deadline, under: event, after: now)
      return try WireCodec.encode(
        try await host.proposeApproval(
          ProposeApproval(command.approval, why: command.why, in: home, deadline: deadline)))
    default:
      return nil
    }
  }
}
