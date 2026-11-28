import Foundation
import LociAgents
import LociMedia
import LociModel

/// What the library takes from the outside world to fetch links and recognize speech, so tests can choose it.
public struct MediaEnvironment: Sendable {
  /// Loci's folder in Application Support, for components, speech models and cookies.
  public let support: URL
  public let runner: any ProgramRunner
  public let network: any Network
  public let sourceNetwork: any Network
  public let transcriber: any Transcribing
  public let diarizer: (any Diarizing)?
  /// Folders searched for components already on this Mac.
  public let searchPaths: [URL]
  /// The system proxy, read each time a program is started.
  public let proxy: @Sendable () -> String?
  /// The language transcripts are translated into.
  public let readerLanguage: String
  /// Whether this Mac has Apple silicon, which decides the components downloaded.
  public let arm: Bool
  /// Fetches articles and papers; `nil` where it is not available, and those jobs fail saying so.
  public let textFetching: (any TextFetching)?
  /// Names speakers in a one-off session on a runtime while there is no tool model; `nil` names nobody then.
  public let transcriptAgent: (@Sendable (Runtime) -> any TranscriptAgent)?
  /// Fetches sources and runs their scripts; over `sourceNetwork` unless given.
  public let dataSources: any DataSourceRunning
  /// Reads the pages data sources read as no one, apart from the library's fetching.
  public let sourcePages: SourcePages
  /// Reads follows and their episodes; over `sourceNetwork` unless given.
  public let follows: any FollowReading

  public init(
    support: URL, runner: any ProgramRunner, network: any Network, transcriber: any Transcribing,
    searchPaths: [URL], proxy: @escaping @Sendable () -> String? = { nil }, readerLanguage: String,
    arm: Bool = true, textFetching: (any TextFetching)? = nil,
    transcriptAgent: (@Sendable (Runtime) -> any TranscriptAgent)? = nil, diarizer: (any Diarizing)? = nil,
    sourceNetwork: (any Network)? = nil, dataSources: (any DataSourceRunning)? = nil,
    sourcePages: SourcePages = SourcePages(hops: HopNetwork()), follows: (any FollowReading)? = nil
  ) {
    self.support = support
    self.runner = runner
    self.network = network
    self.sourceNetwork = sourceNetwork ?? network
    self.transcriber = transcriber
    self.diarizer = diarizer
    self.searchPaths = searchPaths
    self.proxy = proxy
    self.readerLanguage = readerLanguage
    self.arm = arm
    self.textFetching = textFetching
    self.transcriptAgent = transcriptAgent
    self.dataSources = dataSources ?? DataSourceRunner(network: sourceNetwork ?? network)
    self.sourcePages = sourcePages
    self.follows = follows ?? FollowReader(network: sourceNetwork ?? network)
  }

  /// The programs on this Mac, the internet, whisper.cpp, and `~/Library/Application Support/Loci`, with
  /// translations and outlines written by the agent programs `agents` finds.
  public static func system(agents: @escaping @Sendable (Provider) async -> (any AgentDriver)?)
    -> MediaEnvironment
  {
    #if arch(arm64)
      let arm = true
    #else
      let arm = false
    #endif
    return MediaEnvironment(
      support: URL.applicationSupportDirectory.appending(path: "Loci", directoryHint: .isDirectory),
      runner: SystemRunner(), network: SystemNetwork(), transcriber: WhisperTranscriber(),
      searchPaths: ComponentLocator.systemSearchPaths(environment: ProcessInfo.processInfo.environment),
      proxy: { SystemProxy.current() }, readerLanguage: Locale.preferredLanguages.first ?? "en", arm: arm,
      textFetching: WebTextFetcher(network: SystemNetwork()),
      transcriptAgent: { runtime in AgentTranscriptAgent(runtime: runtime, agents: agents) }, diarizer: FluidDiarizer(),
      sourceNetwork: SystemNetwork.anonymous())
  }

  /// Nothing outside: no program starts, nothing downloads, nothing is recognized. For hosts that never
  /// touch video, such as previews and tests of other features.
  public static let disconnected = disconnected(sources: nil)

  /// Nothing outside, with sources run by `sources` and follows read by `follows`.
  public static func disconnected(sources: (any DataSourceRunning)?, follows: (any FollowReading)? = nil)
    -> MediaEnvironment
  {
    MediaEnvironment(
      support: URL(filePath: "/nonexistent/loci-support"), runner: Disconnected(), network: Disconnected(),
      transcriber: Disconnected(), searchPaths: [], readerLanguage: "en", dataSources: sources,
      sourcePages: SourcePages(hops: Disconnected()), follows: follows)
  }
}

private struct Disconnected: ProgramRunner, Network, Transcribing, PageHops {
  func send(_ request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    throw FetchError(reason: "no network here")
  }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError)
    -> ProgramResult
  {
    throw ProgramError(reason: "no programs are started here")
  }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    throw FetchError(reason: "no network here")
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "no network here")
  }

  func transcribe(_ media: URL, model: URL, language: String?, from start: Duration)
    -> AsyncThrowingStream<Heard, any Error>
  {
    AsyncThrowingStream { $0.finish(throwing: TranscribeError(reason: "no recognizer here")) }
  }
}
