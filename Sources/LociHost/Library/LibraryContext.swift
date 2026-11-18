import Foundation
import LociMedia
import LociModel
import LociStore

/// What every stage of a job reads and writes through.
struct LibraryContext: Sendable {
  let store: Store
  let database: StoreDatabase
  let environment: HostEnvironment
  let equipment: Equipment
  let streams: StreamCache
  /// Brings the database up to date and tells the subscriptions.
  let notify: @Sendable (Set<ContentChange>) async -> Void

  var media: MediaEnvironment { environment.media }

  func now() -> Timestamp { environment.now() }

  var settings: HostSettings { (try? store.settings()) ?? HostSettings() }

  /// The language transcripts are translated into: the lessons' language, or the reader's own.
  var targetLanguage: String {
    switch settings.lessonLanguage {
    case .fixed(let tag): tag
    case .learners: media.readerLanguage
    }
  }

  /// The agent chosen in the settings, with its model.
  var agentChoice: AgentChoice {
    let settings = settings
    let provider = settings.agent ?? environment.defaultProvider
    return AgentChoice(provider: provider, model: settings.models[provider] ?? environment.defaultModel)
  }

  var speechModel: SpeechModel { settings.speechModel ?? .recommended }
}

/// Addresses to play items from while they download, as the site last gave them.
actor StreamCache {
  private var streams: [EntityID: OnlineStream] = [:]

  func keep(_ stream: OnlineStream?, for item: EntityID) {
    streams[item] = stream
  }

  /// `nil` when none was given, or the one given has expired by `now`.
  func stream(for item: EntityID, at now: Timestamp) -> OnlineStream? {
    guard let stream = streams[item] else { return nil }
    if let expires = stream.expires, expires <= now { return nil }
    return stream
  }
}

/// Why a stage did not finish.
enum StageStop: Error {
  case wait(Job.Need)
  case fail(Job.Failure)

  static func failed(_ reason: String, _ remedy: Job.Remedy? = .retry, _ cause: Job.Cause? = nil) -> StageStop {
    .fail(Job.Failure(reason: reason, remedy: remedy, cause: cause))
  }
}

/// Runs a store call inside a stage; a failure to read or write fails the stage with a retry.
func stored<Value>(_ body: () throws -> Value) throws(StageStop) -> Value {
  do {
    return try body()
  } catch {
    throw .failed(String(describing: HostError(error)))
  }
}

extension Job.Stage {
  /// The stages an item goes through, in order.
  static func all(for item: Item) -> [Job.Stage] {
    switch item.kind {
    case .article, .paper: [.extract]
    case .video, .audio:
      item.source == nil
        ? [.transcribe, .translate, .outline] : [.resolve, .download, .transcribe, .translate, .outline]
    case .repository: []
    }
  }
}
