import Foundation
import LociModel

extension FakeHost {
  func timers() async throws(HostError) -> Timers { Timers(schedules: [], followUps: [], next: nil) }
  func runs(of schedule: ScheduleRef, limit: Int) async throws(HostError) -> [Run] { [] }
  func pauseSchedule(_ command: PauseSchedule) async throws(HostError) -> Done { Done() }
  func changeScheduleEvery(_ command: ChangeScheduleEvery) async throws(HostError) -> ScheduleEntry {
    throw .notFound(command.schedule.key)
  }
  func removeSchedule(_ command: RemoveSchedule) async throws(HostError) -> Done { Done() }
  func addSchedule(_ command: AddSchedule) async throws(HostError) -> ScheduleEntry {
    throw .invalidRequest("schedules are added by the companion")
  }
  func addFollowUp(_ command: AddFollowUp) async throws(HostError) -> FollowUp {
    throw .invalidRequest("follow-ups are set by the companion")
  }
  func cancelFollowUp(_ command: CancelFollowUp) async throws(HostError) -> Done { Done() }
}
