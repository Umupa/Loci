import Foundation
import LociModel
import Testing

@testable import LociUI

/// H-S8: what the library button and the note under it say after something is kept from a page.
@Suite struct KeepingTests {
  let article: Item
  let paper: Item

  init() throws {
    var entropy = Sample.Seeded()
    func id(_ offset: Double) -> EntityID {
      EntityID(at: Date(timeIntervalSince1970: 1_763_337_600 + offset), entropy: &entropy)
    }
    article = try Item(id: id(1), kind: .article, title: "Raft", source: URL(string: "https://raft.github.io/"))
    paper = try Item(
      id: id(2), kind: .paper, title: "In Search of an Understandable Consensus Algorithm",
      source: URL(string: "https://raft.github.io/raft.pdf"))
  }

  @Test func theButtonTurnsToSavingTheMomentItIsClicked() {
    let keeping = Keeping()
    #expect(keeping.state(library: [], jobs: []) == .saving(nil))
  }

  @Test func itStaysSavingWhileThePageIsFetchedAndShowsHowFarAlong() {
    var keeping = Keeping()
    keeping.took([article.id], refusal: nil)
    #expect(keeping.state(library: [], jobs: []) == .saving(nil))
    let fetching = Job(item: article.id, stage: .fetchPage, state: .running(progress: Fraction(0.4)))
    #expect(keeping.state(library: [article], jobs: [fetching]) == .saving(Fraction(0.4)))
  }

  @Test func anArticleIsSavedOnceItsTextIsInEvenWhileItsCoverIsLookedFor() {
    var keeping = Keeping()
    keeping.took([article.id], refusal: nil)
    let cover = Job(item: article.id, stage: .findCover, state: .running(progress: nil))
    #expect(keeping.state(library: [article], jobs: [cover]) == .saved([article]))
    #expect(keeping.state(library: [article], jobs: []) == .saved([article]))
  }

  @Test func aFailedFetchSaysWhyAndWhatFixesIt() {
    var keeping = Keeping()
    keeping.took([article.id], refusal: nil)
    let failed = Job(
      item: article.id, stage: .extract,
      state: .failed(Job.Failure(reason: "empty", remedy: .retry, cause: .noArticleText)))
    #expect(
      keeping.state(library: [article], jobs: [failed])
        == .stopped(article, .retry, JobLine.Problem(stage: .extract, cause: .noArticleText, reason: "empty")))
  }

  @Test func aSiteThatWantsASignInOffersToSignIn() {
    var keeping = Keeping()
    keeping.took([article.id], refusal: nil)
    let waiting = Job(item: article.id, stage: .fetchPage, state: .waiting(.login(site: "raft.github.io")))
    #expect(
      keeping.state(library: [article], jobs: [waiting]) == .stopped(article, .signIn(site: "raft.github.io"), nil))
  }

  @Test func whatTheHostRefusedIsToldInPlace() {
    var keeping = Keeping()
    keeping.took([], refusal: .offline)
    #expect(keeping.state(library: [], jobs: []) == .refused(.offline))
  }

  @Test func severalKeptAreSavedTogetherOnceAllAreIn() {
    var keeping = Keeping()
    keeping.took([article.id, paper.id], refusal: nil)
    let reading = Job(item: paper.id, stage: .extract, state: .running(progress: Fraction(0.5)))
    #expect(keeping.state(library: [article, paper], jobs: [reading]) == .saving(Fraction(0.75)))
    #expect(keeping.state(library: [article, paper], jobs: []) == .saved([article, paper]))
  }

  @Test func onceTakenBackOutThereIsNothingToTell() {
    var keeping = Keeping()
    keeping.took([article.id], refusal: nil)
    keeping.noting([article])
    #expect(keeping.state(library: [], jobs: []) == nil)
  }
}
