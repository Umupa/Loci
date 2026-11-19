import Foundation
import LociMedia
import LociModel
import LociStore

/// Keeps this copy of Loci up to date with the releases on GitHub. A release is offered only when it is newer
/// than the one running, and installed only when it is signed by the same certificate, so macOS keeps the
/// permissions it gave.
public actor AppUpdater: Updates {
  /// The name of the app inside each release's disk image.
  static let packagedName = "Loci (Beta).app"

  private let environment: UpdateEnvironment
  private var requirement: String?
  private var staged: URL?
  private var listeners: [UUID: AsyncStream<AppUpdate>.Continuation] = [:]
  private var state = AppUpdate.current {
    didSet { for listener in listeners.values { listener.yield(state) } }
  }

  public init(environment: UpdateEnvironment) {
    self.environment = environment
  }

  /// Looks for a newer release now and whenever the environment's ticks say, until the task is cancelled. A
  /// copy that does not know its version, or is not signed with a certificate, never looks.
  public func watch() async {
    guard environment.running != nil,
      let found = try? await AppImage(runner: environment.runner).requirement(of: environment.installed)
    else { return }
    requirement = found
    await look()
    for await _ in environment.ticks() { await look() }
  }

  private func look() async {
    guard let running = environment.running, isIdle,
      let latest = try? await ReleaseFeed(network: environment.network, address: environment.feed).latest(),
      isIdle
    else { return }
    state = latest.version > running ? .available(latest) : .current
  }

  private var isIdle: Bool {
    switch state {
    case .current, .available: true
    case .downloading, .ready, .failed: false
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

  public func download() async {
    let release: AppRelease
    switch state {
    case .available(let offered), .failed(let offered, _): release = offered
    case .current, .downloading, .ready: return
    }
    state = .downloading(release, nil)
    do throws(FetchError) {
      staged = try await fetch(release)
      state = .ready(release)
    } catch {
      state = .failed(release, reason: error.reason)
    }
  }

  private func fetch(_ release: AppRelease) async throws(FetchError) -> URL {
    guard let requirement else { throw FetchError(reason: "this copy of Loci cannot be updated") }
    let support = Support(root: environment.support)
    let tools = AppImage(runner: environment.runner)
    let image = try await environment.network.download(URLRequest(url: release.package)) { [weak self] share in
      Task { await self?.progress(release, share) }
    }
    defer { support.discard(image) }
    let folder: URL
    do {
      folder = try support.scratchFolder()
    } catch {
      throw FetchError(reason: error.localizedDescription)
    }
    let mountPoint = folder.appending(path: "image", directoryHint: .isDirectory)
    let staged = folder.appending(path: Self.packagedName, directoryHint: .isDirectory)
    do throws(FetchError) {
      try await tools.mount(image, at: mountPoint)
      do throws(FetchError) {
        let packaged = mountPoint.appending(path: Self.packagedName, directoryHint: .isDirectory)
        try await tools.verify(packaged, meets: requirement)
        try await tools.copy(packaged, to: staged)
      } catch {
        await tools.unmount(mountPoint)
        throw error
      }
      await tools.unmount(mountPoint)
      try await tools.verify(staged, meets: requirement)
    } catch {
      support.discard(folder)
      throw error
    }
    return staged
  }

  private func progress(_ release: AppRelease, _ share: Fraction?) {
    guard case .downloading(release, let before) = state, Equipment.moved(from: before, to: share) else { return }
    state = .downloading(release, share)
  }

  public func install() async -> Bool {
    guard case .ready(let release) = state, let staged else { return false }
    self.staged = nil
    let support = Support(root: environment.support)
    defer { support.discard(staged.deletingLastPathComponent()) }
    do {
      try support.replaceApp(environment.installed, with: staged)
    } catch {
      state = .failed(release, reason: error.localizedDescription)
      return false
    }
    do throws(FetchError) {
      try await AppImage(runner: environment.runner).open(environment.installed, after: environment.processID)
    } catch {
      state = .failed(release, reason: error.reason)
      return false
    }
    return true
  }
}
