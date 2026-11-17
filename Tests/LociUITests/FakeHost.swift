import Foundation
import LociModel

@testable import LociUI

/// A host with fixed sample data, so the interface can be rendered and tested without a disk.
final class FakeHost: LociModel.Host, CommandHandler {
  let sample: Sample

  init(_ sample: Sample) {
    self.sample = sample
  }

  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    try await command.run(on: self)
  }

  func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    let (feed, continuation) = AsyncStream.makeStream(of: Feed<S.Value>.self)
    Task {
      do throws(HostError) {
        continuation.yield(.value(try await subscription.value(from: self)))
      } catch {
        continuation.yield(.unavailable(error))
      }
    }
    return feed
  }

  func createMentor(_ command: CreateMentor) async throws(HostError) -> Mentor { sample.scheduling }
  func renameMentor(_ command: RenameMentor) async throws(HostError) -> Mentor { sample.scheduling }
  func deleteMentor(_ command: DeleteMentor) async throws(HostError) -> Done { Done() }
  func listMentors() async throws(HostError) -> [Mentor] { sample.mentors }

  func mentorPage(_ mentor: EntityID) async throws(HostError) -> MentorPage {
    guard let page = sample.pages[mentor] else { throw .notFound(mentor.description) }
    return page
  }

  func addTextItem(_ command: AddTextItem) async throws(HostError) -> Item { sample.items[0] }
  func deleteItem(_ command: DeleteItem) async throws(HostError) -> Done { Done() }
  func listItems() async throws(HostError) -> [Item] { sample.items }
  func itemText(_ item: EntityID) async throws(HostError) -> String { sample.text }

  func itemPage(_ item: EntityID) async throws(HostError) -> ItemPage {
    guard let found = sample.items.first(where: { $0.id == item }) else { throw .notFound(item.description) }
    return ItemPage(item: found, text: sample.text, citedBy: found.id == sample.borg.id ? sample.citedBy : [])
  }

  func lessonText(_ lesson: LessonRef) async throws(HostError) -> String { sample.lessonText }

  func lessonCitations(_ lesson: LessonRef) async throws(HostError) -> [Citation] {
    sample.citedBy.map(\.citation)
  }

  func citingLessons(of item: EntityID) async throws(HostError) -> [CitingLesson] { sample.citedBy }
  func search(_ command: Search) async throws(HostError) -> [SearchHit] { [] }
  func readingState(of content: ContentRef) async throws(HostError) -> ReadingState? { nil }
  func saveReadingPosition(_ command: SaveReadingPosition) async throws(HostError) -> Done { Done() }
  func markRead(_ content: ContentRef) async throws(HostError) -> Done { Done() }
  func health() async -> Health { sample.health }
}
