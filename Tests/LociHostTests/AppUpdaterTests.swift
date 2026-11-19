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
    #expect(world.network.asked == [ReleaseFeed.loci])
  }

  @Test func aCopySignedAdHocNeverLooks() async throws {
    let world = try UpdateWorld(latest: "v1.2.0", signature: #"cdhash H"0123""#)
    await world.updater.watch()
    #expect(await world.state() == .current)
    #expect(world.network.asked.isEmpty)
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
}

/// A copy of Loci 1.1.1 in a temporary folder, a release feed, and the programs that unpack and check it.
private struct UpdateWorld {
  let folder: URL
  let installed: URL
  let network: ReleaseNetwork
  let programs: UpdatePrograms
  let updater: AppUpdater
  let release: AppRelease

  init(
    latest tag: String, signature: String = #"identifier "com.loci.native.dev" and certificate leaf = H"ab""#,
    verifies: Bool = true
  ) throws {
    folder = FileManager.default.temporaryDirectory.appending(path: "loci-update-\(UUID().uuidString)")
    installed = folder.appending(path: "Applications/Loci (Beta).app")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appending(path: "marker"))
    let image = URL(string: "https://github.com/Umupa/Loci/releases/download/\(tag)/Loci-Beta.dmg")!
    release = AppRelease(version: ReleaseVersion(tag)!, package: image)
    network = ReleaseNetwork(folder: folder, tag: tag, image: image)
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
  let folder: URL
  let tag: String
  let image: URL

  init(folder: URL, tag: String, image: URL) {
    self.folder = folder
    self.tag = tag
    self.image = image
  }

  var asked: [URL] { requests.withLock { $0 } }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    let url = request.url ?? URL(filePath: "/")
    requests.withLock { $0.append(url) }
    let body = """
      {"tag_name": "\(tag)", "draft": false, "prerelease": false, "assets": [
        {"name": "Loci-Beta.dmg.sha256", "browser_download_url": "\(image.absoluteString).sha256"},
        {"name": "Loci-Beta.dmg", "browser_download_url": "\(image.absoluteString)"}]}
      """
    return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    requests.withLock { $0.append(request.url ?? URL(filePath: "/")) }
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
