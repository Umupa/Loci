import LociModel
import Testing

@testable import LociUI

/// I-S7: the stage ruler and the states of a card in the gallery.
@MainActor
struct StageRulerTests {
  let item = EntityID()
  let video = Item.Kind.video(duration: .seconds(600))
  let stages: [Job.Stage] = [.resolve, .download, .transcribe, .translate]

  func job(_ stage: Job.Stage, _ state: Job.State) -> Job {
    Job(item: item, stage: stage, state: state, stages: stages)
  }

  @Test func segmentsAreAsLongAsTheWorkInThem() {
    let segments = StageRuler.segments(of: job(.download, .running(progress: nil)), kind: video)

    #expect(segments.map(\.stage) == [.download, .transcribe, .translate])
    #expect(segments.map(\.weight) == [3, 2.4, 1.4])
    #expect(
      StageRuler.segments(of: job(.download, .queued), kind: .audio(duration: nil)).map(\.weight) == [1.6, 3, 1.4])
  }

  @Test func stagesBeforeTheCurrentOneAreDoneAndTheRunningOneCarriesItsShare() {
    let segments = StageRuler.segments(of: job(.transcribe, .running(progress: Fraction(0.41))), kind: video)

    #expect(segments.map(\.mark) == [.done, .running(Fraction(0.41)), .upcoming])
  }

  @Test func readingTheLinkShowsAsTheFirstSegmentWithoutAShare() {
    let segments = StageRuler.segments(of: job(.resolve, .running(progress: Fraction(0.5))), kind: video)

    #expect(segments.map(\.mark) == [.running(nil), .upcoming, .upcoming])
  }

  @Test func aPausedJobHatchesItsCurrentStageAndKeepsItsShare() {
    let paused = job(.transcribe, .paused(progress: Fraction(0.41)))

    #expect(StageRuler.segments(of: paused, kind: video).map(\.mark) == [.done, .paused(Fraction(0.41)), .upcoming])
    #expect(CardState(paused) == .paused(Fraction(0.41)))
  }

  @Test func theStageThatFailedOrWaitsForTheReaderTurnsRed() {
    let failed = job(.download, .failed(.init(reason: "HTTP 403")))
    let waiting = job(.download, .waiting(.login(site: "youtube.com")))

    #expect(StageRuler.segments(of: failed, kind: video).map(\.mark) == [.stopped, .upcoming, .upcoming])
    #expect(StageRuler.segments(of: waiting, kind: video).first?.mark == .stopped)
  }

  @Test func aQueuedJobHasNoStageUnderWay() {
    #expect(StageRuler.segments(of: job(.resolve, .queued), kind: video).allSatisfy { $0.mark == .upcoming })
  }

  @Test func theShareReadsAsAWholePercent() {
    #expect(StageRuler.percent(Fraction(0.616)) == "62%")
  }

  @Test func aWaitingJobPutsItsFixInTheMiddleOfTheCover() {
    #expect(CardState(job(.download, .waiting(.login(site: "youtube.com")))) == .needs(.signIn(site: "youtube.com")))
    #expect(CardState(job(.transcribe, .waiting(.speechModel(.base)))) == .needs(.downloadModel(.base)))
  }

  @Test func aPausedJobOffersToCarryOnAndAWorkingOneGlows() {
    #expect(CardState(job(.transcribe, .paused(progress: nil))).pausable)
    #expect(!CardState(job(.transcribe, .paused(progress: nil))).glows)
    #expect(CardState(job(.download, .running(progress: Fraction(0.6)))).glows)
  }

  @Test func finishedWorkLeavesAPlainCover() {
    #expect(CardState(nil) == .ready)
    #expect(CardState(job(.translate, .done)) == .ready)
    #expect(!CardState(nil).isBusy)
  }

  @Test func aJobWaitingItsTurnBeforeAnythingWasMadeIsQueued() {
    #expect(CardState(job(.resolve, .queued)) == .queued)
    #expect(CardState(job(.translate, .queued)) == .working(.translate, nil))
  }
}
