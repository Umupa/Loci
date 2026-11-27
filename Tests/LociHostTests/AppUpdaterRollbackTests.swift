import Foundation
import LociMedia
import LociModel
import LociStore
import Testing

@testable import LociHost

/// UP-S10 and UP-S11: a new copy that does not start gives way to the one it replaced; a copy that cannot be
/// replaced does not download.
@Suite(.timeLimit(.minutes(1)))
struct AppUpdaterRollbackTests {
  @Test func puttingAnUpdateInPlaceKeepsThePreviousCopyAndWatchesTheNewOneStart() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.restart()
    #expect(try world.installedContents() == "new")
    #expect(try world.previousContents() == "old")
    let watcher = try #require(world.watcher)
    #expect(watcher.previousApp == world.previous.appending(path: "Loci (Beta).app").path(percentEncoded: false))
  }

  @Test func theNewVersionStartingForgetsThePreviousCopy() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.restart()
    let relaunched = try UpdateWorld(latest: "v1.2.0", running: "1.2.0", folder: world.folder)
    await relaunched.updater.started()
    await relaunched.launch()
    #expect(!FileManager.default.fileExists(atPath: world.previous.path(percentEncoded: false)))
  }

  @Test func anOlderCopyStartingKeepsThePreviousCopy() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.restart()
    let other = try UpdateWorld(latest: "v1.2.0", folder: world.folder)
    await other.updater.started()
    await other.launch()
    #expect(try world.previousContents() == "old")
  }

  @Test func aVersionThatCouldNotStartIsShownAndNotDownloadedAgain() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.restart()
    try world.rollBack()

    let relaunched = try UpdateWorld(latest: "v1.2.0", folder: world.folder)
    await relaunched.launch()
    #expect(await relaunched.state() == .failed(relaunched.release, .launch))
    #expect(relaunched.network.asked == [relaunched.feed])
  }

  @Test func aVersionThatCouldNotStartCanBeTriedAgainByHand() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.restart()
    try world.rollBack()

    let relaunched = try UpdateWorld(latest: "v1.2.0", folder: world.folder)
    await relaunched.launch()
    await relaunched.updater.retry()
    #expect(await relaunched.state() == .ready(relaunched.release))
  }

  @Test func aNewerReleaseAfterOneThatCouldNotStartDownloads() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.restart()
    try world.rollBack()

    let relaunched = try UpdateWorld(latest: "v1.3.0", folder: world.folder)
    await relaunched.launch()
    #expect(await relaunched.state() == .ready(relaunched.release))
    let later = try UpdateWorld(latest: "v1.3.0", folder: world.folder)
    await later.launch()
    #expect(await later.state() == .ready(later.release))
  }

  @Test(arguments: [AppPlacement.diskImage, .translocated])
  func aCopyThatCannotBeReplacedDoesNotDownload(placement: AppPlacement) async throws {
    let world = try UpdateWorld(latest: "v1.2.0", placement: placement)
    await world.launch()
    #expect(await world.state() == .misplaced)
    await #expect(throws: UpdateCheckError.misplaced) { try await world.updater.check() }
    #expect(world.network.asked.isEmpty)
  }
}

extension UpdateWorld {
  /// Does what the watcher does when the new copy quits before it starts: puts the previous copy back and
  /// records the release.
  func rollBack() throws {
    let files = FileManager.default
    try files.removeItem(at: installed)
    try files.moveItem(at: previous.appending(path: "Loci (Beta).app"), to: installed)
    try files.moveItem(at: previous.appending(path: "release.json"), to: updates.appending(path: "rolled-back.json"))
    try files.removeItem(at: previous)
  }
}
