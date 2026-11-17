import Foundation
import LociModel
import Testing

@testable import LociUI

struct NavigationTests {
  @Test(arguments: [
    ("", PromptInput.empty), ("   \n", .empty),
    ("我想搞懂调度器", .sentence("我想搞懂调度器")), ("  learn Rust ", .sentence("learn Rust")),
    ("https://research.google/pubs/borg/", .link), ("http://example.com", .link),
    ("see https://example.com", .sentence("see https://example.com")), ("example.com", .sentence("example.com")),
    ("ftp://example.com/file", .sentence("ftp://example.com/file")),
  ])
  func theFieldTellsASentenceFromALink(text: String, input: PromptInput) {
    #expect(PromptInput(text) == input)
  }

  @Test func theSidebarListsOnlyKindsThatHaveItems() throws {
    let sample = try Sample()

    #expect(ItemKind.present(in: sample.items) == [.article, .paper])
    #expect(ItemKind.present(in: []).isEmpty)
  }

  @Test func aWindowComesBackWhereItWas() throws {
    let sample = try Sample()
    let window = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])

    #expect(WindowState(restoring: window.text) == window)
    #expect(WindowState(restoring: "") == WindowState())
    #expect(WindowState(restoring: "{not json") == WindowState())
  }

  @Test func aWindowOnADeletedMentorGoesBackToStart() throws {
    let sample = try Sample()
    let window = WindowState(place: .mentor(sample.scheduling.id), pages: [.lesson(sample.filterLesson)])

    #expect(window.keeping(mentors: [sample.scheduling.id]) == window)
    #expect(window.keeping(mentors: [sample.sandbox.id]) == WindowState())
  }

  @Test func commandsWaitForTheHostToBeReady() async throws {
    let deferred = DeferredHost()
    let sample = try Sample()
    async let mentors = deferred.run(ListMentors())
    await deferred.resolve(FakeHost(sample))

    #expect(try await mentors == sample.mentors)
  }
}
