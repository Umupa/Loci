import Foundation
import LociModel

/// `loci schedule` and `loci followup` from a session see and change only the timers of its own home: the main
/// conversation never reads or cancels a project's, nor one project another's. The Timers page uses the host's
/// own commands and sees every one.
extension ToolGateway {
  static func runTimer(_ name: String, _ body: Data, in home: Home, on host: LocalHost)
    async throws(HostError) -> Data?
  {
    switch name {
    case ListTimers.name:
      return try WireCodec.encode(try await host.timers(of: home))
    case CancelFollowUp.name:
      let command = try WireCodec.decode(CancelFollowUp.self, from: body)
      guard try await host.timers(of: home).followUps.contains(where: { $0.id == command.followUp }) else {
        throw .notFound("follow-up \(command.followUp)")
      }
      return try WireCodec.encode(try await host.cancelFollowUp(command))
    case RemoveSchedule.name:
      let command = try WireCodec.decode(RemoveSchedule.self, from: body)
      try await own(command.schedule, in: home, on: host)
      return try WireCodec.encode(try await host.removeSchedule(command))
    case ChangeSchedule.name:
      let command = try WireCodec.decode(ChangeSchedule.self, from: body)
      try await own(command.schedule, in: home, on: host)
      return try WireCodec.encode(try await host.changeSchedule(command))
    default:
      return nil
    }
  }

  private static func own(_ schedule: ScheduleRef, in home: Home, on host: LocalHost) async throws(HostError) {
    guard try await host.timers(of: home).schedules.contains(where: { $0.ref == schedule }) else {
      throw .notFound("schedule \(schedule.key)")
    }
  }
}
