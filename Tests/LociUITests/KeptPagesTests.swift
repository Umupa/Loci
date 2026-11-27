import LociModel
import Testing

@testable import LociUI

struct KeptPagesTests {
  private let a = EntityID()
  private let b = EntityID()
  private let c = EntityID()
  private let d = EntityID()

  @Test func openingAProjectKeepsItsPageAfterThoseMadeBefore() {
    #expect(KeptPages.projects(made: [a, b], open: c, alive: nil) == [a, b, c])
  }

  @Test func turningBackToAKeptProjectMovesNoPage() {
    #expect(KeptPages.projects(made: [a, b, c], open: a, alive: nil) == [a, b, c])
  }

  @Test func pastTheLimitTheOldestMadePageOtherThanTheOpenOneIsLetGo() {
    #expect(KeptPages.projects(made: [a, b, c], open: d, alive: nil) == [b, c, d])
  }

  @Test func aProjectArchivedAwayOrDeletedLosesItsPage() {
    #expect(KeptPages.projects(made: [a, b, c], open: c, alive: [b, c]) == [b, c])
  }

  @Test func theChatOpenKeepsTheProjectsPages() {
    #expect(KeptPages.projects(made: [a, b], open: nil, alive: [a, b]) == [a, b])
  }
}
