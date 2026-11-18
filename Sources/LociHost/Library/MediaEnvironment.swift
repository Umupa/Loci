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
  public let transcriber: any Transcribing
  /// Folders searched for components already on this Mac.
  public let searchPaths: [URL]
  /// The system proxy, read each time a program is started.
  public let proxy: @Sendable () -> String?
  /// The language transcripts are translated into while lessons follow the learner's language.
  public let readerLanguage: String
  /// Whether this Mac has Apple silicon, which decides the components downloaded.
  public let arm: Bool
  /// Fetches articles and papers; `nil` where it is not available, and those jobs fail saying so.
  public let textFetching: (any TextFetching)?
  /// Writes translations and outlines with the agent chosen in the settings; `nil` leaves those stages
  /// waiting for an agent.
  public let transcriptAgent: (@Sendable (AgentChoice) -> any TranscriptAgent)?

  public init(
    support: URL, runner: any ProgramRunner, network: any Network, transcriber: any Transcribing,
    searchPaths: [URL], proxy: @escaping @Sendable () -> String? = { nil }, readerLanguage: String,
    arm: Bool = true, textFetching: (any TextFetching)? = nil,
    transcriptAgent: (@Sendable (AgentChoice) -> any TranscriptAgent)? = nil
  ) {
    self.support = support
    self.runner = runner
    self.network = network
    self.transcriber = transcriber
    self.searchPaths = searchPaths
    self.proxy = proxy
    self.readerLanguage = readerLanguage
    self.arm = arm
    self.textFetching = textFetching
    self.transcriptAgent = transcriptAgent
  }

  /// The programs on this Mac, the internet, whisper.cpp, and `~/Library/Application Support/Loci`, with
  /// translations and outlines written by the agent programs `agents` finds.
  public static func system(agents: @escaping @Sendable (Mentor.Provider) async -> (any AgentDriver)?)
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
      transcriptAgent: { choice in AgentTranscriptAgent(choice: choice, agents: agents) })
  }

  /// Nothing outside: no program starts, nothing downloads, nothing is recognized. For hosts that never
  /// touch video, such as previews and tests of other features.
  public static let disconnected = MediaEnvironment(
    support: URL(filePath: "/nonexistent/loci-support"), runner: Disconnected(), network: Disconnected(),
    transcriber: Disconnected(), searchPaths: [], readerLanguage: "en")
}

private struct Disconnected: ProgramRunner, Network, Transcribing {
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

  func transcribe(_ media: URL, model: URL, from start: Duration) -> AsyncThrowingStream<Heard, any Error> {
    AsyncThrowingStream { $0.finish(throwing: TranscribeError(reason: "no recognizer here")) }
  }
}
