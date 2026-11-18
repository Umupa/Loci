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

  @Test func theSidebarAlwaysListsVideoPodcastsAndArticlesAndPapersOnceThereIsOne() throws {
    let sample = try Sample()

    #expect(ItemKind.listed(in: sample.items) == [.video, .audio, .article, .paper])
    #expect(ItemKind.listed(in: []) == [.video, .audio, .article])
  }

  @Test func theSidebarListsVideoAndPodcastsBeforeText() throws {
    #expect(Array(ItemKind.allCases.prefix(3)) == [.video, .audio, .article])
  }

  @Test func aWindowComesBackWhereItWas() throws {
    let sample = try Sample()
    let window = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])

    #expect(WindowState(restoring: window.text) == window)
    #expect(WindowState(restoring: "") == WindowState())
    #expect(WindowState(restoring: "{not json") == WindowState())
  }

  @Test(arguments: [Place.settings(.general), .settings(.agents), .library(.paper), .start])
  func everyPlaceComesBack(place: Place) {
    #expect(WindowState(restoring: WindowState(place: place).text) == WindowState(place: place))
  }

  @Test func aLessonComesBackAndGoesWithItsMentor() throws {
    let sample = try Sample()
    let lesson = WindowState(place: .lesson(sample.filterLesson), pages: [.item(sample.borg.id)])
    let allItems = Set(sample.items.map(\.id))

    #expect(WindowState(restoring: lesson.text) == lesson)
    #expect(lesson.keeping(mentors: [sample.scheduling.id], items: allItems) == lesson)
    #expect(lesson.keeping(mentors: [sample.sandbox.id], items: allItems) == WindowState())
  }

  @Test func aWindowOnSomethingDeletedGoesBackToStart() throws {
    let sample = try Sample()
    let lesson = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])
    let item = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])
    let allItems = Set(sample.items.map(\.id))

    #expect(lesson.keeping(mentors: [sample.scheduling.id], items: allItems) == lesson)
    #expect(lesson.keeping(mentors: [sample.sandbox.id], items: allItems) == WindowState())
    #expect(item.keeping(mentors: [], items: allItems) == item)
    #expect(item.keeping(mentors: [], items: []) == WindowState())
    #expect(
      WindowState(place: .library(.video)).keeping(mentors: [], items: []) == WindowState(place: .library(.video)))
  }

  @Test func commandsWaitForTheHostToBeReady() async throws {
    let deferred = DeferredHost()
    let sample = try Sample()
    async let mentors = deferred.run(ListMentors())
    await deferred.resolve(FakeHost(sample))

    #expect(try await mentors == sample.mentors)
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
