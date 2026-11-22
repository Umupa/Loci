import Foundation
import LociMedia
import LociModel
import LociStore

extension LibraryContext {
  /// yt-dlp set up with the components, the reader's sign-in and the system proxy. A component that is
  /// missing makes the stage wait for it.
  func ytDlp(needing needed: [Component], anonymous: Bool = false) async throws(StageStop) -> YtDlp {
    for component in needed where await equipment.executable(component) == nil {
      throw .wait(.component(component))
    }
    guard let executable = await equipment.executable(.ytDlp) else { throw .wait(.component(.ytDlp)) }
    let signIn: YtDlp.SignIn =
      if anonymous {
        .init(browser: .none, cookies: nil)
      } else {
        .init(browser: settings.browserLogin, cookies: await equipment.cookies)
      }
    return YtDlp(
      executable: executable, ffmpeg: await equipment.executable(.ffmpeg),
      quickJS: await equipment.executable(.quickJS), signIn: signIn, proxy: media.proxy(), runner: media.runner)
  }

  /// What the reader can do about a failed fetch.
  func stop(_ error: MediaError, at source: URL) async -> StageStop {
    switch error.kind {
    case .needsLogin: .wait(.login(site: source.host() ?? source.absoluteString))
    case .outdated: .failed(error.reason, .updateComponent(.ytDlp), .outdated)
    case .needsJavaScript:
      await equipment.executable(.quickJS) == nil
        ? .wait(.component(.quickJS)) : .failed(error.reason, .updateComponent(.quickJS), .outdated)
    case .cookiesUnreadable: .failed(error.reason, .chooseBrowserLogin, .cookiesUnreadable)
    case .unavailable: .failed(error.reason, .openSource, .unavailable)
    case .network: .failed(error.reason, .retry, .network)
    case .other: .failed(error.reason)
    }
  }
}

/// The library's half of the host: the job queue, what its stages share, and the agent work done on request.
struct LibraryRuntime: Sendable {
  let context: LibraryContext
  let queue: JobQueue
  let picker: KeyPointPicker

  init(store: Store, database: StoreDatabase, environment: HostEnvironment, follower: Follower) {
    let equipment = Equipment(environment: environment) { await follower.follow($0) }
    context = LibraryContext(
      store: store, database: database, environment: environment, equipment: equipment, streams: StreamCache(),
      probes: Probes(), covers: LibraryCovers(store: store, network: environment.media.network),
      models: ModelServices(store: store, environment: environment),
      notify: { await follower.follow($0) })
    queue = JobQueue(context: context)
    picker = KeyPointPicker(context: context, gate: queue.gates.agents)
  }
}
