import Foundation
import LociMedia
import LociModel

/// What updating this copy of Loci takes from the outside world, so tests can choose it.
public struct UpdateEnvironment: Sendable {
  /// The version running; `nil` for a build that does not know it, which never looks for updates.
  public let running: ReleaseVersion?
  /// The app bundle running, which an update replaces.
  public let installed: URL
  /// This process; the new copy opens once it has ended.
  public let processID: Int32
  public let network: any Network
  public let runner: any ProgramRunner
  /// Loci's folder in Application Support, where a download waits until it is installed.
  public let support: URL
  /// Where the latest release is described.
  public let feed: URL
  /// When to look for a newer release again after the first look at start.
  public let ticks: @Sendable () -> AsyncStream<Void>

  public init(
    running: ReleaseVersion?, installed: URL, processID: Int32, network: any Network, runner: any ProgramRunner,
    support: URL, feed: URL = ReleaseFeed.loci, ticks: @escaping @Sendable () -> AsyncStream<Void>
  ) {
    self.running = running
    self.installed = installed
    self.processID = processID
    self.network = network
    self.runner = runner
    self.support = support
    self.feed = feed
    self.ticks = ticks
  }

  /// The app bundle and process running, the published feed, and a look every six hours.
  public static func system(bundle: Bundle = .main) -> UpdateEnvironment {
    UpdateEnvironment(
      running: (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        .flatMap(ReleaseVersion.init),
      installed: bundle.bundleURL, processID: ProcessInfo.processInfo.processIdentifier, network: SystemNetwork(),
      runner: SystemRunner(),
      support: URL.applicationSupportDirectory.appending(path: "Loci", directoryHint: .isDirectory),
      ticks: {
        AsyncStream { continuation in
          let timer = Task {
            while (try? await Task.sleep(for: .seconds(6 * 60 * 60))) != nil { continuation.yield() }
            continuation.finish()
          }
          continuation.onTermination = { _ in timer.cancel() }
        }
      })
  }
}
