import Foundation
import LociMedia
import LociModel
import Synchronization
import Testing

@testable import LociHost

struct AppUpdaterTests {
  @Test func aNewerReleaseIsOffered() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    await world.updater.watch()
    #expect(await world.state() == .available(world.release))
  }

  @Test(arguments: ["v1.1.1", "v1.1.0", "v1.1.1-alpha.1"])
  func aReleaseThatIsNotNewerIsNotOffered(tag: String) async throws {
    let world = try UpdateWorld(latest: tag)
    await world.updater.watch()
    #expect(await world.state() == .current)
    #expect(world.network.asked == [world.feed])
  }

  @Test func aCopySignedAdHocNeverLooks() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", signature: #"cdhash H"0123""#)
    await world.updater.watch()
    #expect(await world.state() == .current)
    #expect(world.network.asked.isEmpty)
  }

  @Test func checkingFindsAnUpdateWithoutWaitingForTheBackgroundCheck() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.updater.check()
    #expect(await world.state() == .available(world.release))
    #expect(world.network.asked == [world.feed])
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
    try await world.updater.check()
    #expect(await world.state() == .available(world.release))
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
    async let watching: Void = world.updater.watch()
    await requested.wait()

    func openReply(on updater: isolated AppUpdater) async { await reply.open() }
    func check(on updater: isolated AppUpdater) async throws {
      async let response: Void = openReply(on: updater)
      try await updater.check()
      await response
    }
    try await check(on: world.updater)
    await watching
    #expect(world.network.asked == [world.feed])
    #expect(await world.state() == .available(world.release))
  }

  @Test func checkingWhileAnUpdateIsReadyKeepsTheDownload() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    try await world.updater.check()
    await world.updater.download()
    let requests = world.network.asked
    try await world.updater.check()
    #expect(await world.state() == .ready(world.release))
    #expect(world.network.asked == requests)
  }

  @Test func aDownloadedReleaseReplacesThisCopyAndOpensOnceItQuits() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    await world.updater.watch()
    await world.updater.download()
    #expect(await world.state() == .ready(world.release))
    #expect(try world.installedContents() == "old")

    #expect(await world.updater.install())
    #expect(try world.installedContents() == "new")
    let opened = try #require(world.programs.calls.last)
    #expect(opened.executable.path() == "/bin/sh")
    #expect(opened.arguments.last == world.installed.path(percentEncoded: false))
    #expect(opened.arguments[1].contains("kill -0 4242"))
  }

  @Test func aReleaseSignedByAnotherCertificateIsRefused() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", verifies: false)
    await world.updater.watch()
    await world.updater.download()
    guard case .failed(let release, _) = await world.state() else {
      Issue.record("the download did not fail")
      return
    }
    #expect(release == world.release)
    #expect(await !world.updater.install())
    #expect(try world.installedContents() == "old")
    #expect(world.programs.calls.contains { $0.arguments.first == "detach" })
  }

  @Test func aFailedDownloadCanBeTriedAgain() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", verifies: false)
    await world.updater.watch()
    await world.updater.download()
    world.programs.verifies = true
    await world.updater.download()
    #expect(await world.state() == .ready(world.release))
  }

  @Test func theBackupFeedIsReadWhenTheFirstCannotBe() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", unreachable: [ReleaseFeed.loci[0]])
    try await world.updater.check()
    #expect(await world.state() == .available(world.release))
    #expect(world.network.asked == ReleaseFeed.loci)
  }

  @Test func aCheckFailsOnlyWhenNoFeedCanBeRead() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", unreachable: Set(ReleaseFeed.loci))
    await #expect(throws: UpdateCheckError.unavailable) { try await world.updater.check() }
    #expect(world.network.asked == ReleaseFeed.loci)
  }

  @Test func theImageComesFromTheMirrorWhenTheFirstPlaceFails() async throws {
    let world = try UpdateWorld(latest: "v1.2.0")
    world.network.unreachable = [world.release.images[0]]
    try await world.updater.check()
    await world.updater.download()
    #expect(await world.state() == .ready(world.release))
    #expect(Array(world.network.asked.suffix(2)) == world.release.images)
  }

  @Test func anImageThatDoesNotMatchItsChecksumIsRefused() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", checksum: String(repeating: "0", count: 64))
    try await world.updater.check()
    await world.updater.download()
    guard case .failed(_, let reason) = await world.state() else {
      Issue.record("the download did not fail")
      return
    }
    #expect(reason.contains("checksum"))
    #expect(!world.programs.calls.contains { $0.arguments.first == "attach" })
  }
}

/// A copy of Loci 1.1.1 in a temporary folder, a release feed, and the programs that unpack and check it.
private struct UpdateWorld {
  let folder: URL
  let installed: URL
  let network: ReleaseNetwork
  let programs: UpdatePrograms
  let updater: AppUpdater
  let release: AppRelease
  let feed = ReleaseFeed.loci[0]
  /// The SHA-256 of the disk image the network serves.
  static let imageChecksum = "00cbbd0ddbda2762798f7009838ed34ca1f12b93965813c7df22943bc62166d1"

  init(
    latest tag: String, signature: String = #"identifier "com.loci.native.dev" and certificate leaf = H"ab""#,
    verifies: Bool = true, checksum: String = UpdateWorld.imageChecksum, unreachable: Set<URL> = [],
    beforeReply: @escaping @Sendable () async -> Void = {}
  ) throws {
    folder = FileManager.default.temporaryDirectory.appending(path: "loci-update-\(UUID().uuidString)")
    installed = folder.appending(path: "Applications/Loci (Beta).app")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appending(path: "marker"))
    let version = ReleaseVersion(tag)!
    let image = URL(string: "https://dl.umupa.fun/loci/Loci-Beta-\(version).dmg")!
    let mirror = URL(string: "https://github.com/Umupa/Loci/releases/download/\(tag)/Loci-Beta-\(version).dmg")!
    release = AppRelease(version: version, image: image, mirrors: [mirror], checksum: checksum)
    network = ReleaseNetwork(folder: folder, latest: release, tag: tag, beforeReply: beforeReply)
    network.unreachable = unreachable
    programs = UpdatePrograms(signature: signature, verifies: verifies)
    updater = AppUpdater(
      environment: UpdateEnvironment(
        running: ReleaseVersion("1.1.1"), installed: installed, processID: 4242, network: network, runner: programs,
        support: folder.appending(path: "Support"), ticks: { AsyncStream { $0.finish() } }))
  }

  func state() async -> AppUpdate? {
    var states = updater.states().makeAsyncIterator()
    return await states.next()
  }

  func installedContents() throws -> String {
    String(decoding: try Data(contentsOf: installed.appending(path: "marker")), as: UTF8.self)
  }
}

private final class ReleaseNetwork: Network {
  private let requests = Mutex<[URL]>([])
  private let disconnected = Mutex(false)
  private let failing = Mutex<Set<URL>>([])
  let folder: URL
  let latest: AppRelease
  let tag: String
  let beforeReply: @Sendable () async -> Void

  init(folder: URL, latest: AppRelease, tag: String, beforeReply: @escaping @Sendable () async -> Void) {
    self.folder = folder
    self.latest = latest
    self.tag = tag
    self.beforeReply = beforeReply
  }

  /// Places that answer with an error.
  var unreachable: Set<URL> {
    get { failing.withLock { $0 } }
    set { failing.withLock { $0 = newValue } }
  }

  var asked: [URL] { requests.withLock { $0 } }

  var offline: Bool {
    get { disconnected.withLock { $0 } }
    set { disconnected.withLock { $0 = newValue } }
  }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    let url = request.url ?? URL(filePath: "/")
    requests.withLock { $0.append(url) }
    if offline || unreachable.contains(url) { throw FetchError(reason: "HTTP 403") }
    await beforeReply()
    let downloads = latest.images.map { "\"\($0.absoluteString)\"" }.joined(separator: ", ")
    let body = """
      {"version": "\(tag.dropFirst())", "sha256": "\(latest.checksum)", "downloads": [\(downloads)]}
      """
    return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    let url = request.url ?? URL(filePath: "/")
    requests.withLock { $0.append(url) }
    if unreachable.contains(url) { throw FetchError(reason: "HTTP 403") }
    progress(Fraction(1))
    let file = folder.appending(path: UUID().uuidString)
    try? Data("dmg".utf8).write(to: file)
    return file
  }
}

/// Answers for `codesign`, `hdiutil`, `ditto` and `sh`. Copying the app writes a new copy whose marker says `new`.
private final class UpdatePrograms: ProgramRunner {
  private let recorded = Mutex<[ProgramCall]>([])
  private let passes: Mutex<Bool>
  let signature: String

  init(signature: String, verifies: Bool) {
    self.signature = signature
    passes = Mutex(verifies)
  }

  var calls: [ProgramCall] { recorded.withLock { $0 } }

  var verifies: Bool {
    get { passes.withLock { $0 } }
    set { passes.withLock { $0 = newValue } }
  }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError)
    -> ProgramResult
  {
    recorded.withLock { $0.append(call) }
    switch (call.executable.lastPathComponent, call.arguments.first) {
    case ("codesign", "-d"):
      return ProgramResult(status: 0, output: "designated => \(signature)\n")
    case ("codesign", "--verify"):
      return verifies ? ProgramResult(status: 0, output: "") : ProgramResult(status: 3, output: "", diagnostics: "nope")
    case ("ditto", _):
      let copy = URL(filePath: call.arguments[1])
      try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
      try? Data("new".utf8).write(to: copy.appending(path: "marker"))
      return ProgramResult(status: 0, output: "")
    default:
      return ProgramResult(status: 0, output: "")
    }
  }
}
