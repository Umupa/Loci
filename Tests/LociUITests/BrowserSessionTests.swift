import Foundation
import Testing

@testable import LociUI

@MainActor
struct BrowserSessionTests {
  static let video = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
  static let article = URL(string: "https://blog.cloudflare.com/pingora")

  @Test func aLinkOpensInTheStartPageItselfAndTheNextInANewTab() {
    let session = BrowserSession()

    session.open(Self.video)
    #expect(session.tabs.count == 1)
    session.open(Self.article)

    #expect(session.tabs.map(\.address) == [Self.video, Self.article])
    #expect(session.current.address == Self.article)
  }

  @Test func aNewTabOpensBesideTheOneInFrontOnTheStartPage() {
    let session = BrowserSession()
    session.open(Self.video)

    session.newTab()

    #expect(session.tabs.count == 2)
    #expect(session.current.atStart)
    #expect(session.current === session.tabs[1])
  }

  @Test func closingATabShowsTheOneBeforeIt() {
    let session = BrowserSession()
    session.open(Self.video)
    let first = session.current
    session.open(Self.article)

    session.close(session.current)

    #expect(session.tabs.count == 1)
    #expect(session.current === first)
  }

  @Test func closingTheLastTabLeavesAStartPage() {
    let session = BrowserSession()
    session.open(Self.video)

    session.close(session.current)

    #expect(session.tabs.count == 1)
    #expect(session.current.atStart)
    #expect(session.current.address == nil)
  }

  @Test func theStartPageKeepsThePageBehindItAndBackReturnsToIt() {
    let session = BrowserSession()
    session.open(Self.video)

    session.current.home()
    #expect(session.current.atStart)
    #expect(session.current.canGoBack)

    session.current.back()
    #expect(!session.current.atStart)
    #expect(session.current.address == Self.video)
  }

  @Test func aFreshStartPageCannotGoBack() {
    #expect(!BrowserSession().current.canGoBack)
  }
}
