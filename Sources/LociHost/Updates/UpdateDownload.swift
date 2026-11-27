import Foundation
import LociMedia
import LociModel
import LociStore

extension AppUpdater {
  /// Takes up the newest copy staged in an earlier run that is newer than this one and still meets the
  /// requirement, and removes every other.
  func restoreStaged() async {
    guard let running = environment.running, let requirement else { return }
    let tools = AppImage(runner: environment.runner)
    for candidate in support.stagedUpdates(appName: Self.packagedName) {
      if staged == nil, candidate.release.version > running,
        (try? await tools.verify(candidate.app, meets: requirement)) != nil
      {
        staged = candidate
        state = .ready(candidate.release)
      } else {
        support.discardStaged(candidate)
      }
    }
  }

  func fetch(_ release: AppRelease) async {
    let result: Result<Support.StagedUpdate, UpdateError>
    do throws(UpdateError) {
      result = .success(try await stage(release))
    } catch {
      result = .failure(error)
    }
    guard fetching?.release == release, !Task.isCancelled else {
      if case .success(let unwanted) = result, unwanted.app != staged?.app { support.discardStaged(unwanted) }
      return
    }
    fetching = nil
    switch result {
    case .success(let arrived):
      if let replaced = staged, replaced.app != arrived.app { support.discardStaged(replaced) }
      staged = arrived
      if case .waiting(_, let busy) = state {
        state = .waiting(release, for: busy)
      } else {
        state = .ready(release)
      }
    case .failure(let error):
      error.log(release)
      guard staged == nil else { return }
      state = .failed(release, error.failure)
      retryLater()
    }
  }

  private func stage(_ release: AppRelease) async throws(UpdateError) -> Support.StagedUpdate {
    guard let requirement else { throw UpdateError(.signature, "this copy of Loci has no requirement to meet") }
    let support = support
    let tools = AppImage(runner: environment.runner)
    let image = try await downloaded(release)
    defer { support.discard(image) }
    let (scratch, folder) = try UpdateError.on(.download) {
      (try support.scratchFolder(), try support.stagingFolder(for: release))
    }
    defer { support.discard(scratch) }
    let mountPoint = scratch.appending(path: "image", directoryHint: .isDirectory)
    let app = folder.appending(path: Self.packagedName, directoryHint: .isDirectory)
    do throws(UpdateError) {
      try await UpdateError.on(.download) { () async throws(FetchError) in try await tools.mount(image, at: mountPoint)
      }
      do throws(UpdateError) {
        let packaged = mountPoint.appending(path: Self.packagedName, directoryHint: .isDirectory)
        try await UpdateError.on(.signature) { () async throws(FetchError) in
          try await tools.verify(packaged, meets: requirement)
        }
        try await UpdateError.on(.download) { () async throws(FetchError) in try await tools.copy(packaged, to: app) }
      } catch {
        await tools.unmount(mountPoint)
        throw error
      }
      await tools.unmount(mountPoint)
      try await UpdateError.on(.signature) { () async throws(FetchError) in
        try await tools.verify(app, meets: requirement)
      }
      return try UpdateError.on(.download) { try support.markStaged(release, appName: Self.packagedName) }
    } catch {
      support.discard(folder)
      throw error
    }
  }

  /// The disk image from the first place that serves one matching the release's checksum. The image collects
  /// in one file across tries and places, and a place that sent more before it broke off is asked again.
  private func downloaded(_ release: AppRelease) async throws(UpdateError) -> URL {
    let part = try UpdateError.on(.download) { try support.partialImage(of: release) }
    var failure = UpdateError(.download, "the release has nowhere to download from")
    var places = release.images[...]
    while let address = places.first {
      let before = support.size(of: part)
      do throws(UpdateError) {
        let image = try await UpdateError.on(.download) { () async throws(FetchError) in
          try await environment.network.download(URLRequest(url: address), keepingPartAt: part) {
            [weak self] share in
            Task { await self?.progress(release, share) }
          }
        }
        guard (try? support.sha256(of: image)) == release.checksum else {
          support.discard(image)
          support.discard(part)
          throw UpdateError(.checksum, "the download from \(address.host() ?? "the mirror") did not match its checksum")
        }
        return image
      } catch {
        if Task.isCancelled { throw error }
        failure = error
        if support.size(of: part) <= before { places = places.dropFirst() }
      }
    }
    throw failure
  }

  private func progress(_ release: AppRelease, _ share: Fraction?) {
    guard case .downloading(release, let before) = state, Equipment.moved(from: before, to: share) else { return }
    state = .downloading(release, share)
  }
}
