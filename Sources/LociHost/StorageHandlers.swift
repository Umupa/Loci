import Foundation
import LociModel
import LociStore

/// O-S6–O-S8: what the media takes, and giving it back or keeping it again.
extension LocalHost {
  public func storage() async throws(HostError) -> StorageReport {
    let items = try await listItems()
    let spaces = items.compactMap { item -> ItemSpace? in
      let audio: Bool
      switch item.kind {
      case .video: audio = false
      case .audio: audio = true
      case .article, .paper, .repository: return nil
      }
      return ItemSpace(
        item: item.id, isAudio: audio, bytes: try? store.mediaBytes(of: item.id), fromLink: item.source != nil)
    }
    let disk = store.disk()
    return StorageReport(
      capacity: disk.capacity, available: disk.available, items: spaces,
      speechModels: await library.context.equipment.modelSpace(), sourceCacheBytes: sources.bytes())
  }

  public func freeMediaSpace(_ item: EntityID) async throws(HostError) -> Done {
    guard try attempt({ try store.item(item) }).source != nil else {
      throw .invalidRequest("only media that came from a link can be watched online instead")
    }
    await library.queue.pause(item)
    try attempt {
      try store.saveImportChoice(choice(of: item, keeping: .online), of: item)
      try store.deleteMedia(of: item)
    }
    await library.queue.forget(item)
    await follow([.item(item), .media])
    return Done()
  }

  public func saveMediaLocally(_ item: EntityID) async throws(HostError) -> Job {
    try attempt { try store.saveImportChoice(choice(of: item, keeping: .local), of: item) }
    await library.queue.begin(item, at: .download)
    await follow([.item(item), .media])
    return await library.queue.job(of: item) ?? Job(item: item, stage: .download, state: .queued)
  }

  /// The item's choice with how it is kept changed; an item taken in before choices were kept starts from the
  /// first one.
  private func choice(of item: EntityID, keeping: ImportChoice.Keeping) throws -> ImportChoice {
    let settings = try store.settings()
    var choice =
      try store.importChoice(of: item)
      ?? ImportChoice.first(
        readerLanguage: library.context.targetLanguage, speechModel: settings.speechModel ?? .recommended)
    choice.keeping = keeping
    return choice
  }
}
