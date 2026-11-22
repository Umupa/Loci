import Foundation
import LociModel
import Testing

@testable import LociUI

struct NavigationTests {
  @Test(arguments: [
    ("", nil), ("   \n", nil), ("我想搞懂调度器", nil), ("  learn Rust ", nil),
    (" https://research.google/pubs/borg/ \n", "https://research.google/pubs/borg/"),
    ("http://example.com", "http://example.com"),
    ("see https://example.com", nil), ("example.com", nil), ("ftp://example.com/file", nil),
  ])
  func textHasAnAddressOnlyWhenItIsAnEntireWebLink(text: String, address: String?) {
    #expect(URL(webLinkText: text)?.absoluteString == address)
  }

  @Test func aWindowComesBackWhereItWas() throws {
    let sample = try Sample()
    let window = WindowState(place: .library(.article), pages: [.item(sample.borg.id)])

    #expect(WindowState(restoring: window.text) == window)
    #expect(WindowState(restoring: "") == WindowState())
    #expect(WindowState(restoring: "{not json") == WindowState())
  }

  @Test(arguments: [Place.settings(.general), .settings(.agents), .library(.article), .talk, .loci])
  func everyPlaceComesBack(place: Place) {
    #expect(WindowState(restoring: WindowState(place: place).text) == WindowState(place: place))
  }

  @Test func aWindowOnTheFormerPapersPageReopensInArticles() throws {
    let saved = #"{"place":{"library":{"_0":"paper"}},"pages":[]}"#
    #expect(WindowState(restoring: saved) == WindowState(place: .library(.article)))

    let paper = try #require(EntityID("01a00000-0000-7000-8000-000000000001"))
    let reading = #"{"place":{"library":{"_0":"paper"}},"pages":[{"item":{"_0":"\#(paper)"}}]}"#
    #expect(WindowState(restoring: reading) == WindowState(place: .library(.article), pages: [.item(paper)]))
  }

  @Test(arguments: [#"{"place":{"start":{}},"pages":[]}"#, #"{"place":{"mentor":{"_0":"x"}},"pages":[]}"#])
  func aPlaceFromBeforeLociOpensTheMainConversation(remembered: String) {
    #expect(WindowState(restoring: remembered) == WindowState(place: .talk))
  }

  /// UI-S24: an item opened from the browser, the main conversation or the library goes back there.
  @Test(arguments: [Place.browser, .talk, .loci, .library(.video)])
  func anItemOpenedFromAPlaceGoesBackToThatPlace(place: Place) throws {
    let sample = try Sample()
    var window = WindowState(place: place).opening(.item(sample.borg.id))

    window.pages.removeLast()

    #expect(window == WindowState(place: place))
  }

  @Test func anItemOpenedFromAnotherGoesBackToTheFirst() throws {
    let sample = try Sample()
    let first = WindowState(place: .talk, pages: [.item(sample.borg.id)])
    var window = first.opening(.item(sample.items[1].id))

    window.pages.removeLast()

    #expect(window == first)
  }

  @Test func openingAnItemAlreadyInTheHistoryStillGoesBackToThePageThatOpenedIt() {
    let item = Page.item(EntityID())
    let other = Page.item(EntityID())
    let from = WindowState(place: .browser, pages: [item, other])
    var window = from.opening(item)

    #expect(window.pages == [item, other, item])
    window.pages.removeLast()
    #expect(window == from)
  }

  /// I-S5, I-S7: cancelling an item from its own page lands back in the library it was opened from.
  @Test func aWindowOnADeletedItemGoesBackToWhereItWasOpenedFrom() throws {
    let sample = try Sample()
    let item = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])

    #expect(item.keeping(items: Set(sample.items.map(\.id))) == item)
    #expect(item.keeping(items: []) == WindowState(place: .library(nil)))
    #expect(WindowState(place: .library(.video)).keeping(items: []) == WindowState(place: .library(.video)))
  }

  @MainActor
  @Test(arguments: ["t=733.14,762.59", "quote=two%20words&pre=before&post=after"])
  func aLinkInAConversationGoesToItsPassage(fragment: String) throws {
    let item = EntityID()
    let address = "loci://library/\(item)#\(fragment)"
    let url = try #require(URL(string: address))
    let locator = try #require(Locator(address))
    var pages: [Page] = []
    var revealed: [Locator] = []
    let openPage = OpenPage { pages.append($0) }
    let show: @MainActor (Locator) -> Void = { revealed.append($0) }

    _ = openPage.follow(url, in: .item(item), reveal: show)
    #expect(revealed == [locator])
    #expect(pages.isEmpty)

    _ = openPage.follow(url, in: .main, reveal: show)
    _ = openPage.follow(url, in: .item(EntityID()), reveal: show)
    #expect(revealed == [locator])
    #expect(pages == [.passage(locator), .passage(locator)])
    #expect(pages.last?.itemID == item)
    #expect(pages.last?.locator == locator)
  }

  @MainActor
  @Test func aBrokenPassageLinkLeavesTheConversationAndTheCurrentPassageAlone() throws {
    let item = EntityID()
    let url = try #require(URL(string: "loci://library/\(item)#t=invalid"))
    let openPage = OpenPage { _ in Issue.record("Opened a page for a broken link") }

    _ = openPage.follow(url, in: .item(item)) { _ in
      Issue.record("Revealed a passage for a broken link")
    }
  }

  @Test func aWindowRemembersTheItemAndLeavesItsPositionToTheReaderAfterRelaunch() throws {
    let item = EntityID()
    let locator = Locator.item(item, .time(try TimeSpan(start: .seconds(42))))
    let window = WindowState(place: .talk, pages: [.passage(locator)])

    #expect(window.keeping(items: [item]) == window)
    #expect(window.keeping(items: []) == WindowState())
    #expect(WindowState(restoring: window.text) == WindowState(place: .talk, pages: [.item(item)]))
  }

  @Test func choosingLociFromTheMainConversationOpensItsPageAndFromAnywhereElseTheConversation() throws {
    let sample = try Sample()

    #expect(WindowState(place: .talk).choosingLoci() == WindowState(place: .loci))
    #expect(WindowState(place: .loci).choosingLoci() == WindowState(place: .talk))
    #expect(WindowState(place: .library(nil)).choosingLoci() == WindowState(place: .talk))
    #expect(
      WindowState(place: .library(nil), pages: [.item(sample.borg.id)]).choosingLoci() == WindowState(place: .talk))
  }

  @Test func commandsWaitForTheHostToBeReady() async throws {
    let deferred = DeferredHost()
    let sample = try Sample()
    async let runtime = deferred.run(ReadRuntime())
    await deferred.resolve(FakeHost(sample))

    #expect(try await runtime == sample.runtime)
  }

  @Test func commandsSentWhileTheHostStartsOverGoToTheNextOne() async throws {
    let deferred = DeferredHost()
    let old = Activity()
    let next = Activity()
    await deferred.resolve(FakeHost(try Sample(), activity: old))
    await deferred.suspend()
    async let runtime = deferred.run(ReadRuntime())
    await deferred.resolve(FakeHost(try Sample(), activity: next))
    _ = try await runtime

    #expect(old.now.begun == 0)
    #expect(next.now.begun == 1)
  }
}
