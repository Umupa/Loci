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
  let probes: Probes
  /// Brings the database up to date and tells the subscriptions.
  let notify: @Sendable (Set<ContentChange>) async -> Void

  var media: MediaEnvironment { environment.media }

  func now() -> Timestamp { environment.now() }

  var settings: HostSettings { (try? store.settings()) ?? HostSettings() }

  /// The language transcripts are translated into: the reader's own.
  var targetLanguage: String { media.readerLanguage }

  /// What Loci runs on.
  var runtime: Runtime { settings.runtime ?? environment.defaultRuntime }

  var speechModel: SpeechModel { settings.speechModel ?? .recommended }

  /// The agent that writes translations, chapters and key points on `runtime`; `nil` follows what Loci runs
  /// on. `nil` when there is no agent to run.
  func transcriptAgent(_ runtime: Runtime?) -> (any TranscriptAgent)? {
    media.transcriptAgent.map { $0(runtime ?? self.runtime) }
  }
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
  /// The stages an item goes through, in order. A video or episode taken in with a choice is recognized
  /// before its media downloads, and goes without the stages the choice leaves out; one taken in before
  /// choices were kept downloads first.
  static func all(for item: Item, choice: ImportChoice?) -> [Job.Stage] {
    switch item.kind {
    case .article, .paper: return [.extract]
    case .repository: return []
    case .video, .audio:
      guard let choice else {
        return item.source == nil
          ? [.transcribe, .translate, .outline] : [.resolve, .download, .transcribe, .translate, .outline]
      }
      var stages: [Job.Stage] = item.source == nil ? [] : [.resolve]
      if choice.recognition != nil { stages.append(.transcribe) }
      if item.source != nil, choice.keeping == .local { stages.append(.download) }
      if choice.translation != nil { stages.append(.translate) }
      return stages + [.outline]
    }
  }
}
