import AppKit
import Foundation
import LociModel
import Testing

@testable import LociUI

/// Sign-ins that answer as told and remember what the browser asked of them.
actor FakeSignIns: BrowserSignIns {
  private(set) var answer: SignInChoice
  private(set) var cookiesTaken = 0

  init(answer: SignInChoice) {
    self.answer = answer
  }

  func choice() -> SignInChoice { answer }

  func use(_ browser: SignInBrowser) throws(SignInFailure) -> [BrowserCookie] {
    answer = .using(browser)
    cookiesTaken += 1
    return []
  }

  func decline() {
    if case .offer(let browser) = answer { answer = .declined(browser) }
  }

  func currentCookies() -> [BrowserCookie] {
    cookiesTaken += 1
    return []
  }
}

@MainActor
@Suite(.onStage)
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

  @Test func pagesAndTheirPopUpsSeeASafariCompatibleBrowserVersion() async throws {
    let session = BrowserSession()
    let view = session.webView(for: session.current)
    view.loadHTMLString("<title>Browser compatibility</title>", baseURL: nil)
    try await eventually("the page to load") { view.title == "Browser compatibility" }

    let userAgent = try #require(try await view.evaluateJavaScript("navigator.userAgent") as? String)
    let version = ProcessInfo.processInfo.operatingSystemVersion
    #expect(userAgent.contains("Version/\(version.majorVersion).\(version.minorVersion) Safari/"))

    let popUpAgent = try await view.evaluateJavaScript("window.open('about:blank')?.navigator.userAgent") as? String
    #expect(popUpAgent == userAgent)
    #expect(session.tabs.count == 2)
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

  @Test func commandWClosesATabThenTheWindow() throws {
    let session = BrowserSession()
    session.open(Self.video)
    session.open(Self.article)
    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
    let close = { window.performClose(nil) }

    #expect(session.handle(event, closeWindow: close))
    #expect(session.current.address == Self.video)
    #expect(window.isVisible)

    #expect(session.handle(event, closeWindow: close))
    #expect(session.current.address == Self.video)
    #expect(!window.isVisible)
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

  @Test func theStartPageOffersSignInsUntilTheReaderSaysNo() async {
    let signIns = FakeSignIns(answer: .offer(.chrome))
    let session = BrowserSession(signIns: signIns)

    await session.checkSignIns()
    #expect(session.signInOffer == .chrome)

    await session.declineSignIns()
    #expect(session.signInOffer == nil)
    await session.checkSignIns()
    #expect(session.signInOffer == nil)
    #expect(await signIns.cookiesTaken == 0)
  }

  @Test func acceptingTakesTheSignInsAndStopsOffering() async {
    let signIns = FakeSignIns(answer: .offer(.edge))
    let session = BrowserSession(signIns: signIns)
    await session.checkSignIns()

    await session.acceptSignIns(from: .edge)

    #expect(session.signInOffer == nil)
    #expect(await signIns.answer == .using(.edge))
    #expect(await signIns.cookiesTaken == 1)
  }

  @Test func signInsInUseAreTakenOnceALaunchWithoutAsking() async {
    let signIns = FakeSignIns(answer: .using(.chrome))
    let session = BrowserSession(signIns: signIns)

    await session.checkSignIns()
    await session.checkSignIns()

    #expect(session.signInOffer == nil)
    #expect(await signIns.cookiesTaken == 1)
  }
}
