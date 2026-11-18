import LociModel
import Testing

@testable import LociUI

struct JobStepsTests {
  private static let video = Item.Kind.video(duration: nil)

  @Test func aVideoBeingRecognizedHasFetchedAndDownloadedAndIsPartWayThrough() {
    let job = Job(item: EntityID(), stage: .transcribe, state: .running(progress: Fraction(0.5)))

    #expect(JobSteps.states(of: job, kind: Self.video).map(\.state) == [.done, .done, .now, .later, .later])
    #expect(JobSteps.progress(of: job, kind: Self.video) == 0.5)
  }

  @Test func anArticleIsOneStepWhicheverPartOfFetchingItIsIn() {
    let resolving = Job(item: EntityID(), stage: .resolve, state: .queued)
    let extracted = Job(item: EntityID(), stage: .extract, state: .done)

    #expect(JobSteps.states(of: resolving, kind: .article).map(\.state) == [.now])
    #expect(JobSteps.progress(of: extracted, kind: .article) == 1)
  }
}
