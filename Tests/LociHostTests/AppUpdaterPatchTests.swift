import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

/// UP-S8: an update from the version running downloads only its patch, and falls back to the whole release.
@Suite(.timeLimit(.minutes(1)))
struct AppUpdaterPatchTests {
  @Test func aPatchForTheRunningVersionIsAllThatDownloads() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch()
    try await world.downloadLatest()
    let state = await world.state()
    #expect(state == .ready(world.release))
    #expect(world.network.asked == [world.feed, world.network.patchURL, world.network.manifestURL])
    await world.updater.restart()
    #expect(try world.installedContents() == "patched")
  }

  @Test func aPatchedCopyThatDoesNotMatchTheManifestFallsBackToTheFullArchive() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch(manifestSays: "something else")
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(world.network.asked.last == world.network.archiveURL)
    await world.updater.restart()
    #expect(try world.installedContents() == "whole")
  }

  @Test func aPatchThatCannotBeAppliedFallsBackToTheFullArchive() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch()
    world.programs.rebuilds = false
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    await world.updater.restart()
    #expect(try world.installedContents() == "whole")
  }

  @Test func aPatchNoPlaceServesFallsBackToTheFullArchive() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch()
    world.network.unreachable = [world.network.patchURL]
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    await world.updater.restart()
    #expect(try world.installedContents() == "whole")
  }

  @Test func aPatchFromAnotherVersionIsNotUsed() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch(from: "1.1.0")
    try await world.downloadLatest()
    #expect(!world.network.asked.contains(world.network.patchURL))
    await world.updater.restart()
    #expect(try world.installedContents() == "whole")
  }

  @Test func aPatchForAnotherReleaseInsideIsNotUsed() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch(declaring: "1.0.0")
    try await world.downloadLatest()
    await world.updater.restart()
    #expect(try world.installedContents() == "whole")
  }

  @Test func anInterruptedPatchContinuesFromWhereItStopped() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.offerPatch()
    world.network.breaksAfterOneByte = 2
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(Array(world.network.partSizes.prefix(3)) == [0, 1, 2])
    #expect(world.network.asked.filter { $0 == world.network.patchURL }.count == 3)
    await world.updater.restart()
    #expect(try world.installedContents() == "patched")
  }

  @Test func theFullUpdateUnpacksTheArchiveWithoutMountingTheImage() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.network.offers.archive = UpdatePrograms.archive(["Loci (Beta).app/marker": "whole"])
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(!world.programs.calls.contains { $0.arguments.first == "attach" })
    #expect(!world.network.asked.contains(world.release.images[0]))
    await world.updater.restart()
    #expect(try world.installedContents() == "whole")
  }

  @Test func aFeedWithoutTheNewFieldsStillUpdatesFromTheDiskImage() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(world.network.asked.last == world.release.images[0])
    #expect(world.programs.calls.contains { $0.arguments.first == "attach" })
    await world.updater.restart()
    #expect(try world.installedContents() == "new")
  }
}

extension UpdateWorld {
  /// Offers the whole release zipped, whose marker says `whole`, and a patch from `from` that rewrites the
  /// marker to `patched`, with the manifest of a release whose marker says `manifestSays`.
  func offerPatch(from: String = "1.1.1", declaring declared: String? = nil, manifestSays: String = "patched") {
    let version = String(network.tag.dropFirst())
    let patch = """
      {"from": "\(declared ?? from)", "to": "\(version)", "changed": [{"path": "marker", "diff": "diffs/0"}],
       "added": [], "removed": [], "links": []}
      """
    let manifest = """
      {"version": "\(version)", "files": [{"path": "marker", "sha256": "\(ReleaseNetwork.sha256(Data(manifestSays.utf8)))",
       "executable": false}], "links": []}
      """
    network.offers = ReleaseNetwork.Offers(
      archive: UpdatePrograms.archive(["Loci (Beta).app/marker": "whole"]), manifest: Data(manifest.utf8),
      patch: (from, UpdatePrograms.archive(["patch.json": patch, "diffs/0": "patched"])))
  }
}
