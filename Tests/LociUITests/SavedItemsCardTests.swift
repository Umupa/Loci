import Foundation
import LociModel
import Testing

@testable import LociUI

struct SavedItemsCardTests {
  private let video: Item
  private let note: Item

  init() throws {
    video = try Item(
      id: EntityID(), kind: .video(duration: .seconds(2052)), title: "Inside the Kubernetes Scheduler",
      authors: ["KubeCon"], source: URL(string: "https://www.youtube.com/watch?v=1"), site: "CNCF")
    note = try Item(id: EntityID(), kind: .article, title: "调度器读书笔记", authors: ["Loci"])
  }

  private func lines(
    _ items: [EntityID], library: [Item]? = nil, jobs: [Job] = [], titles: [EntityID: String] = [:]
  ) -> [SavedItemsCard.Line] {
    SavedItemsCard.lines(items, library: library ?? [video, note], jobs: jobs, titles: titles)
  }

  @Test func anItemWhoseWorkIsGoingShowsWhatItIsDoingAndHowFarAlong() {
    let job = Job(item: video.id, stage: .transcribe, state: .running(progress: Fraction(0.5)))

    let shown = lines([video.id], jobs: [job])

    #expect(shown == [.shown(video, .working(.recognizing, Fraction(0.5)))])
  }

  @Test func anItemWithNoWorkLeftShowsItsBylineInstead() {
    #expect(lines([video.id]) == [.shown(video, .none)])
  }

  @Test func anItemWhoseWorkFailedSaysWhatStoppedIt() {
    let job = Job(item: video.id, stage: .download, state: .failed(Job.Failure(reason: "403", cause: .network)))

    let shown = lines([video.id], jobs: [job])

    let problem = JobLine.Problem(stage: .download, cause: .network, reason: "403")
    #expect(shown == [.shown(video, .action(.retry, problem))])
  }

  @Test func anItemNoLongerInTheLibraryIsDeletedWithTheTitleSeenBefore() {
    let gone = EntityID()

    let shown = lines([gone, video.id], library: [video], titles: [gone: "旧标题"])

    #expect(shown == [.deleted(title: "旧标题"), .shown(video, .none)])
  }

  @Test func aDeletedItemTheCardNeverSawHasNoTitle() {
    #expect(lines([EntityID()]) == [.deleted(title: nil)])
  }

  @Test func nothingShowsUntilTheLibraryIsKnown() {
    #expect(SavedItemsCard.lines([video.id], library: nil, jobs: [], titles: [:]).isEmpty)
  }

  @Test func itemsSavedOneAfterAnotherKeepTheOrderTheyWereSavedIn() {
    #expect(lines([note.id, video.id]) == [.shown(note, .none), .shown(video, .none)])
  }

  @Test func anArticleLociWroteSaysSoInsteadOfASite() {
    let byline = SavedItemByline(note)

    #expect(byline.kind == .article)
    #expect(byline.source == .loci)
    #expect(byline.duration == nil)
  }

  @Test func aVideoSaysItsSiteAndLength() {
    let byline = SavedItemByline(video)

    #expect(byline.kind == .video)
    #expect(byline.source == .named("CNCF"))
    #expect(byline.duration == .seconds(2052))
  }

  @Test func anItemWithNoSiteIsNamedByItsAuthorThenItsLink() throws {
    let authored = try Item(id: EntityID(), kind: .paper, title: "Borg", authors: ["Verma"])
    let linked = try Item(
      id: EntityID(), kind: .article, title: "Log", source: URL(string: "https://engineering.linkedin.com/log"))

    #expect(SavedItemByline(authored).source == .named("Verma"))
    #expect(SavedItemByline(linked).source == .named("engineering.linkedin.com"))
  }
}
