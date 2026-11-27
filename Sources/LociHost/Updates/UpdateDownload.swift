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
    for candidate in files.stagedUpdates() {
      if staged == nil, candidate.release.version > running, !isDeclined(candidate.release),
        (try? await tools.verify(candidate.app, meets: requirement)) != nil
      {
        staged = candidate
        state = .ready(candidate.release)
      } else {
        files.discardStaged(candidate)
      }
    }
  }

  func fetch(_ release: AppRelease) async {
    let result: Result<StagedUpdate, UpdateError>
    do throws(UpdateError) {
      result = .success(try await stage(release))
    } catch {
      result = .failure(error)
    }
    guard fetching?.release == release, !Task.isCancelled else {
      if case .success(let unwanted) = result, unwanted.app != staged?.app { files.discardStaged(unwanted) }
      return
    }
    fetching = nil
    switch result {
    case .success(let arrived):
      if let replaced = staged, replaced.app != arrived.app { files.discardStaged(replaced) }
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

  /// The file from the first place that serves one matching `checksum`. It collects in one file across tries
  /// and places, and a place that sent more before it broke off is asked again. With `reporting`, the bytes
  /// received show as the release's progress.
  func downloaded(
    _ checksum: String, from places: [URL], for release: AppRelease, reporting: Bool = true
  ) async throws(UpdateError) -> URL {
    let part = try UpdateError.on(.download) { try files.partialDownload(checksum: checksum) }
    var failure = UpdateError(.download, "the release has nowhere to download from")
    var remaining = places[...]
    while let address = remaining.first {
      let before = support.size(of: part)
      do throws(UpdateError) {
        let file = try await UpdateError.on(.download) { () async throws(FetchError) in
          try await environment.network.download(URLRequest(url: address), keepingPartAt: part) {
            [weak self] share in
            guard reporting else { return }
            Task { await self?.progress(release, share) }
          }
        }
        guard (try? support.sha256(of: file)) == checksum else {
          support.discard(file)
          support.discard(part)
          throw UpdateError(.checksum, "the download from \(address.host() ?? "the mirror") did not match its checksum")
        }
        return file
      } catch {
        if Task.isCancelled { throw error }
        failure = error
        if support.size(of: part) <= before { remaining = remaining.dropFirst() }
      }
    }
    throw failure
  }

  private func progress(_ release: AppRelease, _ share: Fraction?) {
    guard case .downloading(release, let before) = state, Equipment.moved(from: before, to: share) else { return }
    state = .downloading(release, share)
  }
}
