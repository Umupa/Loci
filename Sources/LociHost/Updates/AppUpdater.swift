import Foundation
import LociMedia
import LociModel
import LociStore
import os

/// Keeps this copy of Loci up to date with the published releases. A newer release downloads by itself and
/// is put in place when Loci quits or restarts; a restart waits while Loci is busy. A release is offered only
/// when it is newer than the one running, and installed only when it is signed by the same certificate, so
/// macOS keeps the permissions it gave.
public actor AppUpdater: Updates {
  /// The name of the app inside each release's disk image.
  static let packagedName = "Loci (Beta).app"
  /// Coming to the front looks again once the last look is older than this.
  static let staleness: TimeInterval = 5 * 60
  /// A failed download tries again after this long.
  static let retryDelay = Duration.seconds(30 * 60)
  /// A copy opened after an update that is not running by then never started, and the previous copy goes back.
  static let openedStart = Duration.seconds(30)
  /// A copy put in place as Loci quits is watched for this long until the person opens it.
  static let quitStart = Duration.seconds(12 * 60 * 60)

  let environment: UpdateEnvironment
  var requirement: String?
  var staged: StagedUpdate?
  /// A release that was put in place and did not start, so the previous copy came back. It and older ones are
  /// not downloaded by themselves.
  var declined: AppRelease?
  /// The release on its way in. It shows while nothing is ready; beside a ready one it downloads quietly.
  var fetching: (release: AppRelease, task: Task<Void, Never>)?
  private var checking: Task<Result<Void, UpdateCheckError>, Never>?
  private var retrying: Task<Void, Never>?
  private(set) var busy: Busy?
  private var lastChecked: Date?
  private var listeners: [UUID: AsyncStream<AppUpdate>.Continuation] = [:]
  var state = AppUpdate.current {
    didSet { for listener in listeners.values { listener.yield(state) } }
  }

  private static let log = Logger(subsystem: "com.loci.native.dev", category: "updates")

  public init(environment: UpdateEnvironment) {
    self.environment = environment
  }

  var support: Support { Support(root: environment.support) }

  var files: UpdateFiles {
    UpdateFiles(support: support, identifier: environment.identifier, appName: Self.packagedName)
  }

  /// Takes up a copy staged before, looks for a newer release, and goes on looking when the ticks say and
  /// when Loci comes to the front, until the task is cancelled. A copy that does not know its version, or is
  /// not signed with a certificate, never looks.
  public func watch() async {
    guard await prepared() else { return }
    guard environment.placement == .replaceable else {
      state = .misplaced
      return
    }
    if environment.identifier == UpdateEnvironment.publishedIdentifier { files.removeEarlierLayout() }
    files.forgetPrevious()
    takeUpRollBack()
    await restoreStaged()
    try? await check()
    let environment = environment
    await withDiscardingTaskGroup { group in
      group.addTask { for await _ in environment.ticks() { try? await self.check() } }
      group.addTask { for await _ in environment.foreground() { await self.cameToFront() } }
      group.addTask { for await now in environment.busy() { await self.busyChanged(now) } }
    }
  }

  /// Whether this copy can update: it knows its version and the requirement the next copy must meet.
  private func prepared() async -> Bool {
    guard environment.running != nil else { return false }
    if requirement != nil { return true }
    guard let found = try? await AppImage(runner: environment.runner).requirement(of: environment.installed)
    else { return false }
    requirement = found
    return true
  }

  public func check() async throws(UpdateCheckError) {
    if let checking {
      return try await checking.value.get()
    }
    let task = Task {
      let result = await look()
      checking = nil
      return result
    }
    checking = task
    try await task.value.get()
  }

  private func look() async -> Result<Void, UpdateCheckError> {
    guard let running = environment.running, await prepared() else { return .failure(.unsupported) }
    guard environment.placement == .replaceable else { return .failure(.misplaced) }
    guard let latest = try? await ReleaseFeed(network: environment.network, address: environment.feed).latest()
    else { return .failure(.unavailable) }
    lastChecked = environment.now()
    if latest.version > running {
      offer(latest)
    } else if staged == nil, fetching == nil, declined == nil {
      retrying?.cancel()
      state = .current
    }
    return .success(())
  }

  private func offer(_ latest: AppRelease) {
    if isDeclined(latest) { return }
    if let staged, staged.release.version >= latest.version { return }
    if let fetching, fetching.release.version >= latest.version { return }
    if case .failed(let failed, _) = state, failed == latest { return }
    startFetching(latest)
  }

  func startFetching(_ release: AppRelease) {
    if let declined, release.version >= declined.version {
      self.declined = nil
      files.forgetRolledBack()
    }
    fetching?.task.cancel()
    retrying?.cancel()
    retrying = nil
    if staged == nil { state = .downloading(release, nil) }
    fetching = (release, Task { await self.fetch(release) })
  }

  /// Tries a failed download again after `retryDelay`, unless something else starts one first.
  func retryLater() {
    let environment = environment
    retrying = Task {
      guard (try? await environment.sleep(Self.retryDelay)) != nil else { return }
      self.retryNow()
    }
  }

  private func retryNow() {
    retrying = nil
    if case .failed(let release, _) = state { startFetching(release) }
  }

  func cameToFront() async {
    if let lastChecked, environment.now().timeIntervalSince(lastChecked) <= Self.staleness { return }
    try? await check()
  }

  private func busyChanged(_ now: Busy?) async {
    busy = now
    guard case .waiting(let release, _) = state else { return }
    if let now {
      state = .waiting(release, for: now)
    } else {
      await installAndQuit()
    }
  }

  public nonisolated func states() -> AsyncStream<AppUpdate> {
    let (stream, continuation) = AsyncStream.makeStream(of: AppUpdate.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { _ in Task { await self.forget(id) } }
    Task { await self.listen(id, continuation) }
    return stream
  }

  private func listen(_ id: UUID, _ continuation: AsyncStream<AppUpdate>.Continuation) {
    listeners[id] = continuation
    continuation.yield(state)
  }

  private func forget(_ id: UUID) {
    listeners[id] = nil
  }

  public func retry() async {
    guard case .failed(let release, _) = state else { return }
    startFetching(release)
    await fetching?.task.value
  }

  /// Marks that this copy has started and shows its window, so the copy it replaced is no longer kept.
  public func started() {
    guard let running = environment.running else { return }
    files.markStarted(running)
  }

  /// Returns once no download is on its way in.
  func settle() async {
    while let task = fetching?.task { await task.value }
  }

  public func restart() async {
    switch state {
    case .ready(let release):
      if let busy {
        state = .waiting(release, for: busy)
      } else {
        await installAndQuit()
      }
    case .waiting:
      await installAndQuit()
    case .current, .downloading, .failed, .misplaced:
      break
    }
  }

  private func installAndQuit() async {
    guard let staged else { return }
    stopFetching()
    let previous: PreviousCopy?
    do {
      previous = try put(staged)
    } catch {
      self.staged = nil
      files.discardStaged(staged)
      fail(staged.release, UpdateError(.install, error.localizedDescription))
      return
    }
    let tools = AppImage(runner: environment.runner)
    do throws(FetchError) {
      if let previous {
        try await tools.watchStart(
          of: environment.installed, previous: previous, after: environment.processID, opens: true,
          appearing: Self.openedStart)
      } else {
        try await tools.open(environment.installed, after: environment.processID)
      }
    } catch {
      fail(staged.release, UpdateError(.install, error.reason))
      return
    }
    await environment.quit()
  }

  private func fail(_ release: AppRelease, _ error: UpdateError) {
    error.log(release)
    state = .failed(release, error.failure)
  }

  public func finishOnQuit() async {
    guard let staged else { return }
    stopFetching()
    let previous: PreviousCopy?
    do {
      previous = try put(staged)
    } catch {
      Self.log.error("the update could not be put in place: \(error.localizedDescription, privacy: .public)")
      return
    }
    guard let previous else { return }
    do throws(FetchError) {
      try await AppImage(runner: environment.runner).watchStart(
        of: environment.installed, previous: previous, after: environment.processID, opens: false,
        appearing: Self.quitStart)
    } catch {
      Self.log.error("the new copy will not be watched as it starts: \(error.reason, privacy: .public)")
    }
  }

  /// Puts the staged copy where this one is, keeping this one until the new one starts; without room to keep
  /// it the update goes ahead all the same. When putting it fails the staged copy stays, so quitting can leave
  /// it for the next launch.
  private func put(_ update: StagedUpdate) throws -> PreviousCopy? {
    let previous: PreviousCopy?
    do {
      previous = try files.keepPrevious(environment.installed, replacedBy: update.release)
    } catch {
      Self.log.error("the copy running could not be kept: \(error.localizedDescription, privacy: .public)")
      previous = nil
    }
    try support.replaceApp(environment.installed, with: update.app)
    staged = nil
    files.discardStaged(update)
    return previous
  }

  /// Shows a release that was put back because it did not start, unless this copy is already as new.
  private func takeUpRollBack() {
    guard let release = files.rolledBack() else { return }
    guard let running = environment.running, release.version > running else {
      files.forgetRolledBack()
      return
    }
    declined = release
    state = .failed(release, .launch)
  }

  func isDeclined(_ release: AppRelease) -> Bool {
    guard let declined else { return false }
    return release.version <= declined.version
  }

  private func stopFetching() {
    fetching?.task.cancel()
    fetching = nil
    retrying?.cancel()
    retrying = nil
  }
}
