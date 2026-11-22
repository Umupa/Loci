import LociModel
import Testing

@testable import LociUI

struct JobStepsTests {
  private static let video = Item.Kind.video(duration: nil)

  @Test func aVideoBeingRecognizedIsHalfWayThroughItsSteps() {
    let job = Job(item: EntityID(), stage: .transcribe, state: .running(progress: Fraction(0.5)))

    #expect(JobSteps.Step(job.stage) == .recognize)
    #expect(JobSteps.progress(of: job, kind: Self.video) == 0.5)
  }

  @MainActor @Test func anArticleFailureStopsOnlyTheStageThatFailed() {
    let job = Job(
      item: EntityID(), stage: .extract, state: .failed(.init(reason: "No readable text")),
      stages: [.fetchPage, .extract, .findCover, .translate])

    let segments = StageRuler.segments(of: job, kind: .article)
    #expect(segments.map(\.stage) == [.fetchPage, .extract, .findCover, .translate])
    #expect(segments.map(\.mark) == [.done, .stopped, .upcoming, .upcoming])
  }

  @Test func anArticleIsOneStepWhicheverPartOfFetchingItIsIn() {
    let resolving = Job(item: EntityID(), stage: .resolve, state: .queued)
    let extracted = Job(item: EntityID(), stage: .extract, state: .done)

    #expect(JobSteps.Step(resolving.stage) == JobSteps.Step(extracted.stage))
    #expect(JobSteps.progress(of: resolving, kind: .article) == 0)
    #expect(JobSteps.progress(of: extracted, kind: .article) == 1)
  }
}
