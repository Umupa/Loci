import CryptoKit
import Foundation
import LociMedia
import LociModel
import LociStore
import Synchronization

@testable import LociHost

/// A copy of Loci 1.1.1 in a temporary folder, a release feed, the programs that unpack and check a release,
/// and the clock, waits, busyness and quitting the updater hears from outside.
struct UpdateWorld {
  let folder: URL
  let installed: URL
  let support: URL
  /// This copy's own update folder.
  let updates: URL
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
    running: String = "1.1.1", identifier: String = UpdateEnvironment.publishedIdentifier,
    placement: AppPlacement = .replaceable, folder given: URL? = nil,
    beforeReply: @escaping @Sendable () async -> Void = {}
  ) throws {
    folder = given ?? FileManager.default.temporaryDirectory.appending(path: "loci-update-\(UUID().uuidString)")
    installed = folder.appending(path: "Applications/Loci (Beta).app")
    support = folder.appending(path: "Support")
    updates = support.appending(path: "updates/\(identifier)")
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
        running: ReleaseVersion(running), installed: installed, identifier: identifier, placement: placement,
        processID: 4242, network: network,
        runner: programs,
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
    let names = (try? FileManager.default.contentsOfDirectory(atPath: updates.path(percentEncoded: false))) ?? []
    return names.filter { ReleaseVersion($0) != nil }.sorted()
  }

  /// The watcher started for the copy just put in place, as the arguments `AppImage.watchStart` passes.
  var watcher: Watcher? {
    guard let call = programs.calls.last(where: { $0.arguments.dropFirst(2).first == "watch" }) else { return nil }
    let given = Array(call.arguments.dropFirst(3))
    return Watcher(app: given[0], previousApp: given[2], opens: given[7] == "yes", pid: given[9])
  }

  struct Watcher: Equatable {
    let app: String
    let previousApp: String
    let opens: Bool
    let pid: String
  }

  var previous: URL { updates.appending(path: "previous") }

  /// What the kept copy of the app that was replaced says.
  func previousContents() throws -> String {
    String(decoding: try Data(contentsOf: previous.appending(path: "Loci (Beta).app/marker")), as: UTF8.self)
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
  private let offering = Mutex(Offers())
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
    let offers = self.offers
    return AppRelease(
      version: version, image: image, mirrors: [mirror], checksum: checksum,
      archive: offers.archive.map { Self.file($0, at: archiveURL) },
      manifest: offers.manifest.map { Self.file($0, at: manifestURL) },
      patches: offers.patch.map {
        [ReleasePatch(from: ReleaseVersion($0.from)!, file: Self.file($0.data, at: patchURL))]
      }
        ?? [],
      notes: offers.notes)
  }

  /// What the feed offers besides the disk image; nothing, as releases up to 1.8.8 described.
  struct Offers: Sendable {
    var archive: Data?
    var manifest: Data?
    var patch: (from: String, data: Data)?
    var notes: [ReleaseNotes] = []
  }

  var offers: Offers {
    get { offering.withLock { $0 } }
    set { offering.withLock { $0 = newValue } }
  }

  var archiveURL: URL { URL(string: "https://dl.umupa.fun/loci/Loci-Beta-\(tag.dropFirst()).zip")! }
  var manifestURL: URL { URL(string: "https://dl.umupa.fun/loci/Loci-Beta-\(tag.dropFirst()).files.json")! }
  var patchURL: URL {
    URL(string: "https://dl.umupa.fun/loci/Loci-Beta-\(tag.dropFirst()).from-\(offers.patch?.from ?? "").patch")!
  }

  private static func file(_ data: Data, at address: URL) -> ReleaseFile {
    ReleaseFile(checksum: sha256(data), size: Int64(data.count), places: [address])
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// The body of `latest.json` for what the feed offers now.
  private var body: String {
    let latest = release
    func file(_ file: ReleaseFile?) -> String? {
      file.map { #"{"sha256": "\#($0.checksum)", "size": \#($0.size ?? 0), "downloads": ["\#($0.places[0])"]}"# }
    }
    var fields = [
      #""version": "\#(tag.dropFirst())""#, #""sha256": "\#(latest.checksum)""#,
      #""downloads": [\#(latest.images.map { "\"\($0.absoluteString)\"" }.joined(separator: ", "))]"#,
    ]
    if let archive = file(latest.archive) { fields.append(#""archive": \#(archive)"#) }
    if let manifest = file(latest.manifest) { fields.append(#""manifest": \#(manifest)"#) }
    if let patch = latest.patches.first {
      fields.append(
        #""patches": [{"from": "\#(patch.from)", "sha256": "\#(patch.file.checksum)", "size": \#(patch.file.size ?? 0), "downloads": ["\#(patch.file.places[0])"]}]"#
      )
    }
    if !latest.notes.isEmpty {
      let notes = latest.notes.map { note in
        let changes = note.changes.map { "- \($0)" }.joined(separator: "\\n")
        return #"{"version": "\#(note.version)", "changes": "\#(changes)"}"#
      }
      fields.append(#""notes": [\#(notes.joined(separator: ", "))]"#)
    }
    return "{" + fields.joined(separator: ", ") + "}"
  }

  /// What the network serves at `url`.
  private func served(at url: URL) -> Data {
    let offers = self.offers
    if url == archiveURL, let archive = offers.archive { return archive }
    if url == manifestURL, let manifest = offers.manifest { return manifest }
    if let patch = offers.patch, url == patchURL { return patch.data }
    return Self.image
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
    let whole = served(at: url)
    let had = (try? Data(contentsOf: part)) ?? Data()
    resumedFrom.withLock { $0.append(had.count) }
    let breaks = breaking.withLock { count in
      defer { count = max(count - 1, 0) }
      return count > 0
    }
    if breaks {
      try? (had + whole.dropFirst(had.count).prefix(1)).write(to: part)
      throw FetchError(reason: "The network connection was lost.")
    }
    for share in reportedShares { progress(share) }
    await hold?.wait()
    try? (had + whole.dropFirst(had.count)).write(to: part)
    return part
  }
}
