import Foundation
import LociModel
import Testing

@testable import LociUI

struct NavigationTests {
  @Test(arguments: [
    ("", PromptInput.empty), ("   \n", .empty),
    ("我想搞懂调度器", .sentence("我想搞懂调度器")), ("  learn Rust ", .sentence("learn Rust")),
    ("https://research.google/pubs/borg/", .link(URL(filePath: "/"))),
    ("http://example.com", .link(URL(filePath: "/"))),
    ("see https://example.com", .sentence("see https://example.com")), ("example.com", .sentence("example.com")),
    ("ftp://example.com/file", .sentence("ftp://example.com/file")),
  ])
  func theFieldTellsASentenceFromALink(text: String, input: PromptInput) {
    #expect(PromptInput(text).withoutAddress == input.withoutAddress)
  }

  @Test func aLinkKeepsItsAddress() {
    #expect(PromptInput(" https://example.com/post ") == .link(URL(string: "https://example.com/post")!))
  }

  @Test func aWindowComesBackWhereItWas() throws {
    let sample = try Sample()
    let window = WindowState(place: .library(.article), pages: [.item(sample.borg.id)])

    #expect(WindowState(restoring: window.text) == window)
    #expect(WindowState(restoring: "") == WindowState())
    #expect(WindowState(restoring: "{not json") == WindowState())
  }

  @Test(arguments: [Place.settings(.general), .settings(.agents), .library(.paper), .talk, .loci])
  func everyPlaceComesBack(place: Place) {
    #expect(WindowState(restoring: WindowState(place: place).text) == WindowState(place: place))
  }

  @Test(arguments: [#"{"place":{"start":{}},"pages":[]}"#, #"{"place":{"mentor":{"_0":"x"}},"pages":[]}"#])
  func aPlaceFromBeforeLociOpensTheMainConversation(remembered: String) {
    #expect(WindowState(restoring: remembered) == WindowState(place: .talk))
  }

  @Test func aWindowOnADeletedItemGoesBackToTheMainConversation() throws {
    let sample = try Sample()
    let item = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])

    #expect(item.keeping(items: Set(sample.items.map(\.id))) == item)
    #expect(item.keeping(items: []) == WindowState(place: .talk))
    #expect(WindowState(place: .library(.video)).keeping(items: []) == WindowState(place: .library(.video)))
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
}

extension PromptInput {
  /// The case alone, so cases can be compared without spelling out addresses.
  fileprivate var withoutAddress: String {
    switch self {
    case .empty: "empty"
    case .sentence(let text): "sentence " + text
    case .link: "link"
    }
  }
}
