import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct AppUpdaterRestartTests {
  @Test func restartingWhileIdlePutsTheNewCopyInPlaceOpensItAndQuits() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    #expect(try world.installedContents() == "old")
    await world.updater.restart()
    #expect(try world.installedContents() == "new")
    let watcher = try #require(world.watcher)
    #expect(watcher.app == world.installed.path(percentEncoded: false))
    #expect(watcher.opens)
    #expect(watcher.pid == "4242")
    #expect(world.quitCount == 1)
  }

  @Test func aNewCopyThatCannotBePutInPlaceFailsAsAnInstall() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    try FileManager.default.removeItem(at: world.installed.deletingLastPathComponent())
    await world.updater.restart()
    #expect(await world.state() == .failed(world.release, .install))
    #expect(world.quitCount == 0)
  }

  @Test func restartingWhileBusyWaitsAndSaysWhatFor() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    let watching = Task { await world.updater.watch() }
    await world.until { if case .ready = $0 { true } else { false } }
    await world.untilListening()
    world.busy.send(.answering)
    await world.updater.settleBusy(.answering)
    await world.updater.restart()
    #expect(await world.state() == .waiting(world.release, for: .answering))
    world.busy.send(.library)
    #expect(await world.until { $0 == .waiting(world.release, for: .library) } != nil)
    #expect(try world.installedContents() == "old")
    #expect(world.quitCount == 0)
    watching.cancel()
  }

  @Test func aWaitingUpdateRestartsOnceNothingIsBusy() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    let watching = Task { await world.updater.watch() }
    await world.until { if case .ready = $0 { true } else { false } }
    await world.untilListening()
    world.busy.send(.running)
    await world.updater.settleBusy(.running)
    await world.updater.restart()
    world.busy.send(nil)
    while world.quitCount == 0 { await Task.yield() }
    #expect(try world.installedContents() == "new")
    #expect(world.quitCount == 1)
    watching.cancel()
  }

  @Test func restartingAgainWhileWaitingRestartsAtOnce() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    let watching = Task { await world.updater.watch() }
    await world.until { if case .ready = $0 { true } else { false } }
    await world.untilListening()
    world.busy.send(.answering)
    await world.updater.settleBusy(.answering)
    await world.updater.restart()
    await world.updater.restart()
    #expect(try world.installedContents() == "new")
    #expect(world.quitCount == 1)
    watching.cancel()
  }

  @Test func aNewerReleaseThatArrivesWhileWaitingIsTheOneRestartedInto() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    let watching = Task { await world.updater.watch() }
    await world.until { if case .ready = $0 { true } else { false } }
    await world.untilListening()
    world.busy.send(.answering)
    await world.updater.settleBusy(.answering)
    await world.updater.restart()
    world.network.tag = "v1.3.0"
    try await world.downloadLatest()
    #expect(await world.state() == .waiting(world.release, for: .answering))
    watching.cancel()
  }

  @Test func quittingWithAReadyUpdateReplacesThisCopyWithoutOpeningIt() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    await world.updater.finishOnQuit()
    #expect(try world.installedContents() == "new")
    #expect(world.watcher?.opens == false)
    #expect(world.quitCount == 0)
    #expect(world.stagedFolders.isEmpty)
  }

  @Test func quittingWithoutAReadyUpdateChangesNothing() async throws {
    let world = try UpdateWorld(latest: "v1.1.1")
    try await world.downloadLatest()
    await world.updater.finishOnQuit()
    #expect(try world.installedContents() == "old")
  }

  @Test func aReplacementThatFailsOnQuitKeepsTheUpdateForNextLaunch() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    try FileManager.default.removeItem(at: world.installed.deletingLastPathComponent())
    await world.updater.finishOnQuit()
    #expect(world.stagedFolders == ["1.2.0"])

    try FileManager.default.createDirectory(at: world.installed, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: world.installed.appending(path: "marker"))
    let relaunched = try UpdateWorld(latest: "v1.2.0", folder: world.folder)
    await relaunched.launch()
    #expect(await relaunched.state() == .ready(relaunched.release))
    #expect(!relaunched.network.asked.contains(relaunched.release.images[0]))
  }

  @Test func aStagedCopyThatIsNoLongerNewerIsRemovedAtLaunch() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    let installed = try UpdateWorld(latest: "v1.2.0", running: "1.2.0", folder: world.folder)
    await installed.launch()
    #expect(installed.stagedFolders.isEmpty)
    #expect(await installed.state() == .current)
  }

  @Test func aStagedCopyThatNoLongerMeetsTheRequirementIsRemovedAtLaunch() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    let relaunched = try UpdateWorld(latest: "v1.2.0", verifies: false, folder: world.folder)
    await relaunched.launch()
    #expect(relaunched.stagedFolders.isEmpty)
    guard case .failed = await relaunched.state() else {
      Issue.record("the restaged copy was accepted")
      return
    }
  }

  @Test func comingToTheFrontChecksWhenTheLastCheckIsOverFiveMinutesOld() async throws {
    let world = try UpdateWorld(latest: "v1.1.1")
    try await world.updater.check()
    world.advance(5 * 60 + 1)
    await world.updater.cameToFront()
    #expect(world.network.asked == [world.feed, world.feed])
  }

  @Test func comingToTheFrontSoonAfterACheckDoesNotCheckAgain() async throws {
    let world = try UpdateWorld(latest: "v1.1.1")
    try await world.updater.check()
    world.advance(4 * 60)
    await world.updater.cameToFront()
    #expect(world.network.asked == [world.feed])
  }

  @Test func comingToTheFrontIsHeardWhileWatching() async throws {
    let world = try UpdateWorld(latest: "v1.1.1")
    let watching = Task { await world.updater.watch() }
    await world.untilListening()
    world.advance(10 * 60)
    world.foreground.send(())
    while world.network.asked.count < 2 { await Task.yield() }
    #expect(world.network.asked == [world.feed, world.feed])
    watching.cancel()
  }

  @Test func aFailedDownloadIsRetriedAfterThirtyMinutes() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", verifies: false)
    try await world.downloadLatest()
    #expect(await world.sleeper.asked == [.seconds(30 * 60)])
    world.programs.verifies = true
    await world.sleeper.wake()
    await world.until { if case .ready = $0 { true } else { false } }
    #expect(await world.state() == .ready(world.release))
  }
}

extension UpdateWorld {
  /// Waits until the updater listens for busyness and coming to the front.
  func untilListening() async {
    while !busy.listening || !foreground.listening { await Task.yield() }
  }
}

extension AppUpdater {
  /// Waits until the updater has heard that Loci is busy with `busy`.
  func settleBusy(_ busy: Busy?) async {
    while self.busy != busy { await Task.yield() }
  }
}
