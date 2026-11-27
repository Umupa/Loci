import Foundation
import LociMedia
import LociModel
import Synchronization

@testable import LociHost

/// A copy of Loci 1.1.1 in a temporary folder, a release feed, the programs that unpack and check a release,
/// and the clock, waits, busyness and quitting the updater hears from outside.
struct UpdateWorld {
  let folder: URL
  let installed: URL
  let support: URL
  let network: ReleaseNetwork
  let programs: UpdatePrograms
  let updater: AppUpdater
  let feed = ReleaseFeed.loci
  let clock = Shared(Date(timeIntervalSince1970: 1_800_000_000))
  let sleeper = Sleeper()
  let busy = Signal<Busy?>()
  let foreground = Signal<Void>()
  /// Quitting asks the updater to finish on quit first, as the app delegate does.
  let quits = Shared(0)
  /// The SHA-256 of the disk image the network serves.
  static let imageChecksum = "00cbbd0ddbda2762798f7009838ed34ca1f12b93965813c7df22943bc62166d1"

  init(
    latest tag: String, signature: String = #"identifier "com.loci.native.dev" and certificate leaf = H"ab""#,
    verifies: Bool = true, checksum: String = UpdateWorld.imageChecksum, unreachable: Set<URL> = [],
    running: String = "1.1.1", folder given: URL? = nil, beforeReply: @escaping @Sendable () async -> Void = {}
  ) throws {
    folder = given ?? FileManager.default.temporaryDirectory.appending(path: "loci-update-\(UUID().uuidString)")
    installed = folder.appending(path: "Applications/Loci (Beta).app")
    support = folder.appending(path: "Support")
    if given == nil {
      try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
      try Data("old".utf8).write(to: installed.appending(path: "marker"))
    }
    network = ReleaseNetwork(folder: folder, tag: tag, checksum: checksum, beforeReply: beforeReply)
    network.unreachable = unreachable
    programs = UpdatePrograms(signature: signature, verifies: verifies)
    let (clock, sleeper, busy, foreground, quits) = (clock, sleeper, busy, foreground, quits)
    let quitting = Shared<AppUpdater?>(nil)
    updater = AppUpdater(
      environment: UpdateEnvironment(
        running: ReleaseVersion(running), installed: installed, processID: 4242, network: network, runner: programs,
        support: support, ticks: { AsyncStream { $0.finish() } }, foreground: { foreground.stream() },
        busy: { busy.stream() }, now: { clock.value }, sleep: { try await sleeper.sleep($0) },
        quit: {
          await quitting.value?.finishOnQuit()
          quits.change { $0 += 1 }
        }))
    quitting.change { [updater] in $0 = updater }
  }

  /// The release the feed describes now.
  var release: AppRelease { network.release }

  func state() async -> AppUpdate? {
    var states = updater.states().makeAsyncIterator()
    return await states.next()
  }

  /// Waits until the state is one `matches` accepts, and returns it.
  @discardableResult
  func until(_ matches: (AppUpdate) -> Bool) async -> AppUpdate? {
    for await state in updater.states() where matches(state) { return state }
    return nil
  }

  /// Watches as the app does at launch until the first look and its download are done.
  func launch() async {
    let started = Shared(false)
    let watching = Task {
      await updater.watch()
      started.change { $0 = true }
    }
    while !started.value, !(busy.listening && foreground.listening) { await Task.yield() }
    await updater.settle()
    watching.cancel()
  }

  /// Checks and waits for the download that follows.
  func downloadLatest() async throws {
    try await updater.check()
    await updater.settle()
  }

  func advance(_ seconds: TimeInterval) {
    clock.change { $0 += seconds }
  }

  func installedContents() throws -> String {
    String(decoding: try Data(contentsOf: installed.appending(path: "marker")), as: UTF8.self)
  }

  var quitCount: Int { quits.value }

  var stagedFolders: [String] {
    let updates = support.appending(path: "updates")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: updates.path(percentEncoded: false))) ?? []
    return names.filter { !$0.hasSuffix(".partial") }.sorted()
  }
}

/// A value the test and the updater both reach.
final class Shared<Value: Sendable>: Sendable {
  private let mutex: Mutex<Value>

  init(_ value: Value) {
    mutex = Mutex(value)
  }

  var value: Value { mutex.withLock { $0 } }

  func change(_ body: (inout Value) -> Void) {
    mutex.withLock { body(&$0) }
  }
}

/// Values sent to whoever is listening, as the busyness and foreground streams the updater watches.
final class Signal<Value: Sendable>: Sendable {
  private let listeners = Mutex<[AsyncStream<Value>.Continuation]>([])

  func stream() -> AsyncStream<Value> {
    let (stream, continuation) = AsyncStream.makeStream(of: Value.self)
    listeners.withLock { $0.append(continuation) }
    return stream
  }

  func send(_ value: Value) {
    for listener in listeners.withLock({ $0 }) { listener.yield(value) }
  }

  var listening: Bool { listeners.withLock { !$0.isEmpty } }
}

/// Waits that last until the test wakes them, remembering how long each was meant to be.
actor Sleeper {
  private(set) var asked: [Duration] = []
  private var sleeping: [CheckedContinuation<Void, any Error>] = []

  func sleep(_ duration: Duration) async throws {
    asked.append(duration)
    try await withCheckedThrowingContinuation { sleeping.append($0) }
  }

  func wake() {
    for each in sleeping { each.resume() }
    sleeping = []
  }
}

final class ReleaseNetwork: Network {
  private let requests = Mutex<[URL]>([])
  private let disconnected = Mutex(false)
  private let failing = Mutex<Set<URL>>([])
  private let latestTag: Mutex<String>
  private let breaking = Mutex(0)
  private let resumedFrom = Mutex<[Int]>([])
  private let shares = Mutex<[Fraction]>([Fraction(1)])
  private let holding = Mutex<Latch?>(nil)
  let folder: URL
  let checksum: String
  let beforeReply: @Sendable () async -> Void
  static let image = Data("dmg".utf8)

  init(folder: URL, tag: String, checksum: String, beforeReply: @escaping @Sendable () async -> Void) {
    self.folder = folder
    latestTag = Mutex(tag)
    self.checksum = checksum
    self.beforeReply = beforeReply
  }

  var tag: String {
    get { latestTag.withLock { $0 } }
    set { latestTag.withLock { $0 = newValue } }
  }

  var release: AppRelease {
    let version = ReleaseVersion(tag)!
    let image = URL(string: "https://dl.umupa.fun/loci/Loci-Beta-\(version).dmg")!
    let mirror = URL(string: "https://github.com/Umupa/Loci/releases/download/\(tag)/Loci-Beta-\(version).dmg")!
    return AppRelease(version: version, image: image, mirrors: [mirror], checksum: checksum)
  }

  var unreachable: Set<URL> {
    get { failing.withLock { $0 } }
    set { failing.withLock { $0 = newValue } }
  }

  var asked: [URL] { requests.withLock { $0 } }

  var offline: Bool {
    get { disconnected.withLock { $0 } }
    set { disconnected.withLock { $0 = newValue } }
  }

  /// How many of the next downloads break off after the first byte.
  var breaksAfterOneByte: Int {
    get { breaking.withLock { $0 } }
    set { breaking.withLock { $0 = newValue } }
  }

  /// The shares each download reports before it finishes.
  var reportedShares: [Fraction] {
    get { shares.withLock { $0 } }
    set { shares.withLock { $0 = newValue } }
  }

  /// Keeps each download from finishing, once it has reported its shares, until it opens.
  var hold: Latch? {
    get { holding.withLock { $0 } }
    set { holding.withLock { $0 = newValue } }
  }

  /// How many bytes the part held when each download began.
  var partSizes: [Int] { resumedFrom.withLock { $0 } }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    let url = request.url ?? URL(filePath: "/")
    requests.withLock { $0.append(url) }
    if offline || unreachable.contains(url) { throw FetchError(reason: "HTTP 403") }
    await beforeReply()
    let latest = release
    let downloads = latest.images.map { "\"\($0.absoluteString)\"" }.joined(separator: ", ")
    let body = """
      {"version": "\(tag.dropFirst())", "sha256": "\(latest.checksum)", "downloads": [\(downloads)]}
      """
    return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    try await download(request, keepingPartAt: folder.appending(path: UUID().uuidString), progress: progress)
  }

  func download(
    _ request: URLRequest, keepingPartAt part: URL, progress: @escaping @Sendable (Fraction?) -> Void
  ) async throws(FetchError) -> URL {
    let url = request.url ?? URL(filePath: "/")
    requests.withLock { $0.append(url) }
    if unreachable.contains(url) { throw FetchError(reason: "HTTP 403") }
    let had = (try? Data(contentsOf: part)) ?? Data()
    resumedFrom.withLock { $0.append(had.count) }
    let breaks = breaking.withLock { count in
      defer { count = max(count - 1, 0) }
      return count > 0
    }
    if breaks {
      try? (had + Self.image.dropFirst(had.count).prefix(1)).write(to: part)
      throw FetchError(reason: "The network connection was lost.")
    }
    for share in reportedShares { progress(share) }
    await hold?.wait()
    try? (had + Self.image.dropFirst(had.count)).write(to: part)
    return part
  }
}

/// Answers for `codesign`, `hdiutil`, `ditto` and `sh`. Copying the app writes a new copy whose marker says `new`.
final class UpdatePrograms: ProgramRunner {
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
