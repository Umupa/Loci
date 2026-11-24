import Foundation
import LociModel

@testable import LociUI

/// A host with fixed sample data, so the interface can be rendered and tested without a disk.
final class FakeHost: LociModel.Host, CommandHandler {
  let sample: Sample
  let modelSettings: (any ModelSettingsAccess)?
  let piWork: Transfer?
  /// The design's library; when given, it is the library and the conversations this host serves.
  let library: SampleLibrary?
  /// The library's video is still having its speech recognized.
  let recognizing: Bool
  /// Loci is answering in the main conversation.
  let working: Bool
  /// The picture the person chose for Loci.
  let avatar: Avatar?
  /// The panel column beside the main conversation; empty unless a test gives one.
  let panels: PanelColumn
  /// Counts what is asked and answered, so a test can wait for the view's data.
  let activity: Activity
  /// The last way something was taken in; `nil` gives the first default.
  let lastChoice: ImportChoice?
  /// How far the library's key points have got.
  let keyPoints: SampleKeyPoints
  /// The courses this host serves; none unless a test gives them.
  let courses: SampleCourses?
  /// What the model menus offer; DeepSeek and OpenRouter unless a test gives none.
  let modelOptions: ModelOptions

  init(
    _ sample: Sample, library: SampleLibrary? = nil, recognizing: Bool = false, working: Bool = false,
    avatar: Avatar? = nil, panels: PanelColumn = PanelColumn(slots: []), activity: Activity = Activity(),
    lastChoice: ImportChoice? = nil, keyPoints: SampleKeyPoints = .picked,
    modelSettings: (any ModelSettingsAccess)? = nil, piWork: Transfer? = nil, courses: SampleCourses? = nil,
    modelOptions: ModelOptions = .sample
  ) {
    self.modelOptions = modelOptions
    self.courses = courses
    self.lastChoice = lastChoice
    self.modelSettings = modelSettings
    self.piWork = piWork
    self.sample = sample
    self.library = library
    self.keyPoints = keyPoints
    self.recognizing = recognizing
    self.working = working
    self.avatar = avatar
    self.panels = panels
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
  func modelSettingsAccess() async -> (any ModelSettingsAccess)? { modelSettings }
  func modelOptions() async throws(HostError) -> ModelOptions { modelOptions }

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
    let translated = found.id == sample.borg.id ? sample.translation : nil
    return ItemPage(item: found, text: sample.text, translatable: translated != nil, translation: translated)
  }

  func search(_ command: Search) async throws(HostError) -> [SearchHit] { [] }
  func readingState(of content: ContentRef) async throws(HostError) -> ReadingState? {
    guard case .item(let item) = content else { return nil }
    return library?.states[item]
  }
  func saveReadingPosition(_ command: SaveReadingPosition) async throws(HostError) -> Done { Done() }
  func markRead(_ content: ContentRef) async throws(HostError) -> Done { Done() }
  func notes(on content: ContentRef) async throws(HostError) -> [Note] {
    if case .lesson(_, let lesson) = content { return (try? courses?.notes(on: lesson)) ?? [] }
    if let library, case .item(let item) = content { return (try? library.notes(on: item)) ?? [] }
    return sample.notes
  }
  func addNote(_ command: AddNote) async throws(HostError) -> Note { sample.notes[0] }
  func setNoteThought(_ command: SetNoteThought) async throws(HostError) -> Note { sample.notes[0] }
  func setWholeThought(_ command: SetWholeThought) async throws(HostError) -> Note? { nil }
  func deleteNote(_ command: DeleteNote) async throws(HostError) -> Done { Done() }

  func health() async -> Health { sample.health }
}

/// The key points of the sample library: not asked for, being picked, or picked.
enum SampleKeyPoints {
  case none, picking, picked
}

extension ModelOptions {
  /// DeepSeek with one model and OpenRouter with two, the first used for everything.
  static let sample: ModelOptions = {
    let deepSeek = ModelGroup(
      provider: ModelProviderID(.deepSeek), preset: .deepSeek, name: "", models: ["deepseek-chat"])
    let openRouter = ModelGroup(
      provider: ModelProviderID(.openRouter), preset: .openRouter, name: "",
      models: ["gemini-3-flash", "kimi-k3"])
    let chosen = ModelChoice(provider: ModelProviderID(.openRouter), model: "gemini-3-flash")
    return ModelOptions(
      groups: [deepSeek, openRouter],
      uses: ModelUses(
        translation: ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-chat"),
        transcripts: chosen))
  }()
}
