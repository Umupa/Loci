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
  let covers: LibraryCovers
  let models: ModelServices
  /// Brings the database up to date and tells the subscriptions.
  let notify: @Sendable (Set<ContentChange>) async -> Void

  var media: MediaEnvironment { environment.media }

  func now() -> Timestamp { environment.now() }

  var settings: HostSettings { (try? store.settings()) ?? HostSettings() }

  /// The language transcripts are translated into: the reader's own.
  var targetLanguage: String { translationSettings.language ?? media.readerLanguage }

  var translationSettings: TranslationSettings {
    (try? store.modelSettings().translation) ?? TranslationSettings()
  }

  var speechModel: SpeechModel { settings.speechModel ?? .recommended }

  func transcriptWork(_ chosen: Runtime?) async throws(HostError) -> TranscriptWork? {
    let (translation, direct) = try await models.selection()
    if let direct {
      let service = direct.service
      return TranscriptWork(
        agent: direct, parallelism: models.parallelism, usesRuntime: false,
        identity: ["model", service.provider.rawValue, service.endpoint.absoluteString, service.model],
        settings: translation, cache: models.cache)
    }
    guard let (agent, runtime) = await runtimeWriter(chosen) else { return nil }
    return TranscriptWork(
      agent: agent, parallelism: 1, usesRuntime: true,
      identity: ["runtime", runtime.provider.rawValue, runtime.model ?? "", runtime.effort?.rawValue ?? ""],
      settings: translation, cache: models.cache)
  }

  func runtimeWriter(_ preferred: Runtime?) async -> (any RuntimeTranscriptAgent, Runtime)? {
    let agents = HostAgents(store: store, environment: environment, library: self)
    let selection = await agents.selection(preferred)
    let runtime = selection.runtime
    if runtime.provider == .bundledPi {
      guard let driver = await agents.driver(for: selection) else { return nil }
      return (AgentTranscriptAgent(runtime: runtime, agents: { _ in driver }), runtime)
    }
    return media.transcriptAgent.map { ($0(runtime), runtime) }
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
    case .article:
      let stages: [Job.Stage] = item.source == nil ? [] : [.fetchPage, .extract, .findCover]
      return choice?.translation == nil ? stages : stages + [.translate]
    case .paper: return [.extract]
    case .repository: return []
    case .video, .audio:
      guard let choice else {
        let start: [Job.Stage] = item.source == nil ? [] : [.resolve, .download]
        return start + [.transcribe] + (item.isPodcast ? [.diarize] : []) + [.translate, .outline]
      }
      var stages: [Job.Stage] = item.source == nil ? [] : [.resolve]
      if choice.recognition != nil { stages.append(.transcribe) }
      if item.isPodcast, choice.recognition != nil || choice.siteSubtitles { stages.append(.diarize) }
      if item.source != nil, choice.keeping == .local { stages.append(.download) }
      if choice.translation != nil { stages.append(.translate) }
      return stages + [.outline]
    }
  }
}
