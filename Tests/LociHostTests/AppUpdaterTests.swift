import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct AppUpdaterTests {
  @Test func aNewerReleaseDownloadsByItself() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    await world.launch()
    #expect(await world.state() == .ready(world.release))
    #expect(Array(world.network.asked.suffix(1)) == [world.release.images[0]])
  }

  @Test func downloadProgressFollowsTheBytesReceived() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    let hold = Latch(open: false)
    world.network.reportedShares = [Fraction(0.5)]
    world.network.hold = hold
    try await world.updater.check()
    let seen = await world.until { if case .downloading(_, _?) = $0 { true } else { false } }
    #expect(seen == .downloading(world.release, Fraction(0.5)))
    await hold.open()
    await world.updater.settle()
    #expect(await world.state() == .ready(world.release))
  }

  @Test(arguments: ["v1.1.1", "v1.1.0", "v1.1.1-alpha.1"])
  func aReleaseThatIsNotNewerIsNotDownloaded(tag: String) async throws {
    let world = try UpdateWorld(latest: tag)
    await world.launch()
    #expect(await world.state() == .current)
    #expect(world.network.asked == [world.feed])
  }

  @Test func aCopySignedAdHocNeverLooks() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", signature: #"cdhash H"0123""#)
    await world.launch()
    #expect(await world.state() == .current)
    #expect(world.network.asked.isEmpty)
  }

  @Test func checkingTheLatestVersionSucceeds() async throws {
    let world = try UpdateWorld(latest: "v1.1.1")
    try await world.updater.check()
    #expect(await world.state() == .current)
    #expect(world.network.asked == [world.feed])
  }

  @Test func aFailedCheckCanBeRetriedWithoutClaimingTheAppIsUpToDate() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.network.offline = true
    await #expect(throws: UpdateCheckError.unavailable) { try await world.updater.check() }
    world.network.offline = false
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
  }

  @Test func aManualCheckReportsWhenTheCopyCannotUpdate() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", signature: #"cdhash H"0123""#)
    await #expect(throws: UpdateCheckError.unsupported) { try await world.updater.check() }
    #expect(world.network.asked.isEmpty)
  }

  @Test func aManualCheckSharesTheRequestAlreadyRunningInTheBackground() async throws {
    let requested = Latch(open: false)
    let reply = Latch(open: false)
    let world = try UpdateWorld(latest: "v1.2.0") {
      await requested.open()
      await reply.wait()
    }
    let watching = Task { await world.updater.watch() }
    await requested.wait()

    func openReply(on updater: isolated AppUpdater) async { await reply.open() }
    func check(on updater: isolated AppUpdater) async throws {
      async let response: Void = openReply(on: updater)
      try await updater.check()
      await response
    }
    try await check(on: world.updater)
    await world.updater.settle()
    watching.cancel()
    #expect(world.network.asked.filter { $0 == world.feed }.count == 1)
    #expect(await world.state() == .ready(world.release))
  }

  @Test func checkingAgainWhileAnUpdateIsReadyKeepsTheDownload() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    let requests = world.network.asked
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(world.network.asked == requests + [world.feed])
  }

  @Test func aReleaseSignedByAnotherCertificateIsRefused() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", verifies: false)
    try await world.downloadLatest()
    #expect(await world.state() == .failed(world.release, .signature))
    await world.updater.restart()
    #expect(try world.installedContents() == "old")
    #expect(world.programs.calls.contains { $0.arguments.first == "detach" })
  }

  @Test func aFailedDownloadCanBeTriedAgain() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", verifies: false)
    try await world.downloadLatest()
    world.programs.verifies = true
    await world.updater.retry()
    #expect(await world.state() == .ready(world.release))
  }

  @Test func aCheckFailsWhenTheFeedCannotBeRead() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", unreachable: [ReleaseFeed.loci])
    await #expect(throws: UpdateCheckError.unavailable) { try await world.updater.check() }
    #expect(world.network.asked == [ReleaseFeed.loci])
  }

  @Test func theImageComesFromTheMirrorWhenTheFirstPlaceFails() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.network.unreachable = [world.release.images[0]]
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(Array(world.network.asked.suffix(2)) == world.release.images)
  }

  @Test func anImageThatDoesNotMatchItsChecksumIsRefused() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", checksum: String(repeating: "0", count: 64))
    try await world.downloadLatest()
    #expect(await world.state() == .failed(world.release, .checksum))
    #expect(!world.programs.calls.contains { $0.arguments.first == "attach" })
  }

  @Test func aReleaseNoPlaceServesFailsAsADownload() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.network.unreachable = Set(world.release.images)
    try await world.downloadLatest()
    #expect(await world.state() == .failed(world.release, .download))
  }

  @Test func anInterruptedDownloadContinuesFromWhereItStopped() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.network.breaksAfterOneByte = 2
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(world.network.partSizes == [0, 1, 2])
    #expect(world.network.asked.filter { $0 == world.release.images[0] }.count == 3)
  }

  @Test func aNewerReleaseReplacesTheOneAlreadyReady() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    world.network.tag = "v1.3.0"
    try await world.downloadLatest()
    #expect(await world.state() == .ready(world.release))
    #expect(world.release.version == ReleaseVersion("1.3.0"))
    #expect(world.stagedFolders == ["1.3.0"])
  }

  @Test func theReadyReleaseStaysWhileANewerOneDownloads() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    let first = world.release
    world.network.tag = "v1.3.0"
    let hold = Latch(open: false)
    world.network.hold = hold
    try await world.updater.check()
    #expect(await world.state() == .ready(first))
    await world.updater.restart()
    #expect(try world.installedContents() == "new")
    #expect(world.quitCount == 1)
  }

  @Test func aNewerReleaseThatFailsKeepsTheReadyOne() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.downloadLatest()
    let first = world.release
    world.network.tag = "v1.3.0"
    world.programs.verifies = false
    try await world.downloadLatest()
    #expect(await world.state() == .ready(first))
  }
}
