import Foundation
import LociMedia
import LociModel
import LociStore

extension AppUpdater {
  /// Downloads `release` and stages its copy, checked and signed like this one: from the patch for the
  /// version running when there is one, and from the whole release when there is none or it does not work.
  func stage(_ release: AppRelease) async throws(UpdateError) -> StagedUpdate {
    guard let requirement else { throw UpdateError(.signature, "this copy of Loci has no requirement to meet") }
    if let running = environment.running, let patch = release.patch(from: running) {
      do throws(UpdateError) {
        return try await stagePatched(
          release, from: running, patch: patch.patch, manifest: patch.manifest, requirement: requirement)
      } catch {
        if Task.isCancelled { throw error }
        UpdateError(error.failure, "the patch did not work, so the whole release downloads: \(error.detail)")
          .log(release)
      }
    }
    if let archive = release.archive {
      return try await stageArchive(release, archive: archive, requirement: requirement)
    }
    return try await stageImage(release, requirement: requirement)
  }

  private func stagePatched(
    _ release: AppRelease, from running: ReleaseVersion, patch: ReleaseFile, manifest: ReleaseFile,
    requirement: String
  ) async throws(UpdateError) -> StagedUpdate {
    let support = support
    let tools = AppImage(runner: environment.runner)
    let file = try await downloaded(patch.checksum, from: patch.places, for: release)
    defer { support.discard(file) }
    let listing = try await downloaded(manifest.checksum, from: manifest.places, for: release, reporting: false)
    defer { support.discard(listing) }
    return try await staging(release) { scratch, app throws(UpdateError) in
      let unpacked = scratch.appending(path: "patch", directoryHint: .isDirectory)
      try await UpdateError.on(.download) { () async throws(FetchError) in try await tools.expand(file, into: unpacked)
      }
      let (contents, files) = try UpdateError.on(.download) {
        (try support.readPatch(in: unpacked), try support.readManifest(listing))
      }
      guard contents.from == running, contents.to == release.version, files.version == release.version else {
        throw UpdateError(.download, "the patch is from \(contents.from) to \(contents.to)")
      }
      try UpdateError.on(.download) { try support.copyApp(environment.installed, to: app) }
      var rebuilt: [String: URL] = [:]
      for (index, change) in contents.changed.enumerated() {
        let output = scratch.appending(path: "rebuilt-\(index)")
        try await UpdateError.on(.download) { () async throws(FetchError) in
          try await tools.rebuild(
            app.appending(path: change.path), into: output, with: unpacked.appending(path: change.diff))
        }
        rebuilt[change.path] = output
      }
      try UpdateError.on(.download) {
        try support.apply(contents, unpackedIn: unpacked, rebuilt: rebuilt, to: app, manifest: files)
      }
      try UpdateError.on(.checksum) { try support.check(app, against: files) }
      try await UpdateError.on(.signature) { () async throws(FetchError) in
        try await tools.verify(app, meets: requirement)
      }
    }
  }

  private func stageArchive(
    _ release: AppRelease, archive: ReleaseFile, requirement: String
  ) async throws(UpdateError) -> StagedUpdate {
    let support = support
    let tools = AppImage(runner: environment.runner)
    let file = try await downloaded(archive.checksum, from: archive.places, for: release)
    defer { support.discard(file) }
    return try await staging(release) { scratch, app throws(UpdateError) in
      let unpacked = scratch.appending(path: "archive", directoryHint: .isDirectory)
      try await UpdateError.on(.download) { () async throws(FetchError) in try await tools.expand(file, into: unpacked)
      }
      try UpdateError.on(.download) {
        try support.copyApp(unpacked.appending(path: Self.packagedName, directoryHint: .isDirectory), to: app)
      }
      try await UpdateError.on(.signature) { () async throws(FetchError) in
        try await tools.verify(app, meets: requirement)
      }
    }
  }

  private func stageImage(_ release: AppRelease, requirement: String) async throws(UpdateError)
    -> StagedUpdate
  {
    let support = support
    let tools = AppImage(runner: environment.runner)
    let image = try await downloaded(release.checksum, from: release.images, for: release)
    defer { support.discard(image) }
    return try await staging(release) { scratch, app throws(UpdateError) in
      let mountPoint = scratch.appending(path: "image", directoryHint: .isDirectory)
      try await UpdateError.on(.download) { () async throws(FetchError) in
        try await tools.mount(image, at: mountPoint)
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
    }
  }

  /// Runs `build` to put `release`'s app in its staging folder, using a scratch folder that goes afterwards,
  /// and marks it staged; when `build` fails the staging folder goes too.
  private func staging(
    _ release: AppRelease, _ build: (_ scratch: URL, _ app: URL) async throws(UpdateError) -> Void
  ) async throws(UpdateError) -> StagedUpdate {
    let support = support
    let (scratch, folder) = try UpdateError.on(.download) {
      (try files.scratchFolder(), try files.stagingFolder(for: release))
    }
    defer { support.discard(scratch) }
    do throws(UpdateError) {
      try await build(scratch, folder.appending(path: Self.packagedName, directoryHint: .isDirectory))
      return try UpdateError.on(.download) { try files.markStaged(release) }
    } catch {
      support.discard(folder)
      throw error
    }
  }
}
