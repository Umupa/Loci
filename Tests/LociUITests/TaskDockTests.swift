import LociModel
import Testing

@testable import LociUI

/// I-S8: the task capsule floats over the gallery while work is under way.
@MainActor
struct TaskDockTests {
  private let failed = Job(item: EntityID(), stage: .extract, state: .failed(Job.Failure(reason: "no text")))
  private let running = Job(item: EntityID(), stage: .fetchPage, state: .running(progress: nil))

  @Test func onlyFailedTasksLeaveNoCapsule() {
    #expect(TaskDock.arrange([failed]) == nil)
  }

  @Test func aFailedTaskWaitsInTheListBehindTheWorkUnderWay() throws {
    let arranged = try #require(TaskDock.arrange([failed, running]))

    #expect(arranged.lead == running)
    #expect(arranged.rest == [failed])
  }
}
