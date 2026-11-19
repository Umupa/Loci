import Foundation
import LociModel

@testable import LociUI

/// A host with fixed sample data, so the interface can be rendered and tested without a disk.
final class FakeHost: LociModel.Host, CommandHandler {
  let sample: Sample
  /// The design's library; when given, it is the library and the conversations this host serves.
  let library: SampleLibrary?
  /// The library's video is still having its speech recognized.
  let recognizing: Bool
  /// Loci is answering in the main conversation.
  let working: Bool
  /// The picture the person chose for Loci.
  let avatar: Avatar?
  /// Counts what is asked and answered, so a test can wait for the view's data.
  let activity: Activity

  init(
    _ sample: Sample, library: SampleLibrary? = nil, recognizing: Bool = false, working: Bool = false,
    avatar: Avatar? = nil, activity: Activity = Activity()
  ) {
    self.sample = sample
    self.library = library
    self.recognizing = recognizing
    self.working = working
    self.avatar = avatar
    self.activity = activity
  }

  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    activity.begin()
    defer { activity.end() }
    return try await command.run(on: self)
  }

  func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    let (feed, continuation) = AsyncStream.makeStream(of: Feed<S.Value>.self)
    activity.begin()
    Task { [activity] in
      defer { activity.end() }
      do throws(HostError) {
        continuation.yield(.value(try await subscription.value(from: self)))
      } catch {
        continuation.yield(.unavailable(error))
      }
    }
    return feed
  }

  func upload(_ file: LocalFile) async throws(HostError) -> Upload { Upload(id: sample.items[0].id) }
  func localFile(_ place: LocalPlace) async -> LocalFile? { nil }

  func addTextItem(_ command: AddTextItem) async throws(HostError) -> Item { sample.items[0] }
  func deleteItems(_ command: DeleteItems) async throws(HostError) -> Done { Done() }
  func restoreDeleted() async throws(HostError) -> [Item] { [] }
  func renameItem(_ command: RenameItem) async throws(HostError) -> Item { throw .notFound(command.item.description) }
  func setCover(_ command: SetCover) async throws(HostError) -> Done { Done() }
  func listItems() async throws(HostError) -> [Item] { library?.items ?? sample.items }
  func itemText(_ item: EntityID) async throws(HostError) -> String { sample.text }

  func itemPage(_ item: EntityID) async throws(HostError) -> ItemPage {
    if let library, let found = library.items.first(where: { $0.id == item }) {
      return ItemPage(item: found, text: found.id == library.article.id ? SampleLibrary.articleText : nil)
    }
    guard let found = sample.items.first(where: { $0.id == item }) else { throw .notFound(item.description) }
    return ItemPage(item: found, text: sample.text)
  }

  func search(_ command: Search) async throws(HostError) -> [SearchHit] { [] }
  func readingState(of content: ContentRef) async throws(HostError) -> ReadingState? {
    guard case .item(let item) = content else { return nil }
    return library?.states[item]
  }
  func saveReadingPosition(_ command: SaveReadingPosition) async throws(HostError) -> Done { Done() }
  func markRead(_ content: ContentRef) async throws(HostError) -> Done { Done() }
  func notes(on content: ContentRef) async throws(HostError) -> [Note] {
    if let library, case .item(let item) = content { return (try? library.notes(on: item)) ?? [] }
    return sample.notes
  }
  func addNote(_ command: AddNote) async throws(HostError) -> Note { sample.notes[0] }
  func setNoteThought(_ command: SetNoteThought) async throws(HostError) -> Note { sample.notes[0] }
  func deleteNote(_ command: DeleteNote) async throws(HostError) -> Done { Done() }

  func health() async -> Health { sample.health }
}
