import Foundation
import LociMedia
import LociModel
import LociRemote
import LociStore
import Network
import Testing
import WebKit

@testable import LociHost

@Suite(.timeLimit(.minutes(1)))
struct SourceScenarioTests {
  @Test func everyLociSessionCanReadAndTheSocketCarriesTheWholeText() async throws {
    let content = String(repeating: "First line of text.\n", count: 150_000) + "last line"
    let network = SourceFixtureNetwork(content)
    try await withSourceHost(network: network) { host, place, _, _ in
      let request = try requestForFile()
      let socket = DataFolder.socket(in: place.root)
      for _ in 0..<100 where !FileManager.default.fileExists(atPath: socket.path) {
        try await Task.sleep(for: .milliseconds(20))
      }
      let sessions: [LocalSession?] = [
        .conversation(.main), .conversation(.item(EntityID())), .panelRefresh(EntityID()), nil,
      ]
      for session in sessions {
        let reply = try await LocalSocket.call(.init(session: session, request: request), at: socket)
        guard case .value(let data) = reply else {
          Issue.record("Source request failed: \(reply)")
          return
        }
        let text = try JSONDecoder().decode(String.self, from: data)
        #expect(text.utf8.count == content.utf8.count)
        #expect(text == content)
      }
      #expect(await network.requests == 1)
      #expect(try await host.run(ListItems()).isEmpty)
      #expect(
        try FileManager.default.contentsOfDirectory(
          atPath: place.store.agentFolder.appending(path: "workspace").path
        ).isEmpty)
    }
  }

  @Test func storageReportsSourceBytesAndClearingLetsTheAppFetchAgain() async throws {
    let network = SourceFixtureNetwork("A file")
    try await withSourceHost(network: network) { host, _, _, _ in
      let updates = host.subscribe(StorageUse())
      _ = try await host.run(ReadSource(url: fileURL()))
      #expect(await value(updates) { ($0.sourceCacheBytes ?? 0) > 0 } != nil)
      _ = try await host.run(ClearSourceCache())
      #expect(await value(host.subscribe(StorageUse())) { $0.sourceCacheBytes == 0 } != nil)
      #expect(try await host.run(ReadSource(url: fileURL())) == "A file")
      #expect(await network.requests == 2)
    }
  }

  @Test func startupAndTheFirstIdleTickEachDayRemoveExpiredSources() async throws {
    let network = SourceFixtureNetwork("Still online")
    try await withSourceHost(network: network, seedExpired: true) { host, _, world, _ in
      #expect(await value(host.subscribe(StorageUse())) { $0.sourceCacheBytes == 0 } != nil)
      let fetched = try await host.run(ReadSource(url: fileURL()))
      let report = try await host.storage()
      #expect(fetched == "Still online")
      #expect((report.sourceCacheBytes ?? 0) > 0)
      world.advance(minutes: 14 * 24 * 60)
      world.tick()
      #expect(await value(host.subscribe(StorageUse())) { $0.sourceCacheBytes == 0 } != nil)
    }
  }

  @Test func aDailyCleanupWaitsForLociToFinishItsTurn() async throws {
    let network = SourceFixtureNetwork("Still useful")
    let agent = ManualAgent()
    try await withSourceHost(network: network, agent: agent) { host, _, world, _ in
      _ = try await host.run(ReadSource(url: fileURL()))
      _ = try await host.run(SendMessage(to: .main, text: "Keep working"))
      #expect(await working(host))
      world.advance(minutes: 14 * 24 * 60)
      world.tick()
      try await Task.sleep(for: .milliseconds(50))
      let busy = try await host.storage()
      #expect((busy.sourceCacheBytes ?? 0) > 0)
      await agent.sessions.first?.finish()
      let settled = await settled(host)
      #expect(settled != nil)
      world.tick()
      #expect(await value(host.subscribe(StorageUse())) { $0.sourceCacheBytes == 0 } != nil)
    }
  }

  @Test func aSecondRequestForTheSamePinnedRepoUsesTheExistingCheckout() async throws {
    let network = SourceFixtureNetwork("")
    let commit = try #require(CommitID(String(repeating: "b", count: 40)))
    let git = SourceFixtureGit(commit: commit)
    let place = Place()
    defer { place.remove() }
    let media = MediaEnvironment(
      support: place.root, runner: git, network: network, transcriber: FakeTranscriber([]),
      searchPaths: [], readerLanguage: "en")
    try await withSourceHost(network: network, media: media) { host, _, _, _ in
      let url = try #require(URL(string: "https://github.com/Owner/Repository.git"))
      let alias = try #require(URL(string: "https://github.com/owner/repository/"))
      let first = try await host.run(FetchSourceRepository(url: url))
      let second = try await host.run(FetchSourceRepository(url: alias, commit: commit))
      #expect(first == second)
      let file = URL(filePath: first.path).appending(path: "README.md")
      #expect(try String(contentsOf: file, encoding: .utf8) == "A repo")
      #expect(await git.fetches == 1)
      _ = try await host.run(ClearSourceCache())
      #expect(!FileManager.default.fileExists(atPath: first.path))
    }
  }

  @Test func hashRoutedPagesHaveIndependentBodiesAndOrdinaryAnchorsShareOne() async throws {
    let html = """
      <html><body><main><article>
        <h1>Source documentation</h1>
        <p id="words">Ordinary document text for reading.</p>
        <script>
          const page = location.hash;
          if (page === "#/first") document.getElementById("words").textContent = "The first route.";
          if (page === "#/last") document.getElementById("words").textContent = "The last route.";
          if (page === "#!next") document.getElementById("words").textContent = "The hashbang route.";
          if (page === "#anchor") document.getElementById("words").textContent = "The ordinary anchor was sent.";
        </script>
      </article></main></body></html>
      """
    let site = try await SourcePageSite.start { _ in html }
    defer { site.stop() }
    try await withSourceHost(network: SourceFixtureNetwork("")) { host, _, _, _ in
      let pages = [
        ("#/first", "The first route."),
        ("#/last", "The last route."),
        ("#!next", "The hashbang route."),
        ("#anchor", "Ordinary document text for reading."),
        ("#another-anchor", "Ordinary document text for reading."),
      ]
      for (fragment, expected) in pages {
        let url = try #require(URL(string: site.url.absoluteString + fragment))
        let text = try await host.run(ReadSource(url: url))
        #expect(text.contains(expected))
      }
    }
  }

  @Test @MainActor func websitesAreReadWithoutTheBuiltInBrowsersLogin() async throws {
    let example = "loci_source_test_session=example"
    let site = try await SourcePageSite.start { request in
      let text = request.contains(example) ? "Private account text." : "Public signed-out text."
      return "<html><body><article><h1>Source page</h1><p>\(text)</p></article></body></html>"
    }
    defer { site.stop() }
    let cookie = try #require(
      HTTPCookie(properties: [
        .domain: "127.0.0.1", .path: site.url.path(), .name: "loci_source_test_session", .value: "example",
      ]))
    let cookies = WKWebsiteDataStore.default().httpCookieStore
    await cookies.setCookie(cookie)
    defer { Task { await cookies.deleteCookie(cookie) } }
    let browser = WebTextFetcher(network: SystemNetwork())
    let signedIn = try await browser.article(at: site.url, html: nil)
    #expect(signedIn.markdown.contains("Private account text."))

    let result = try await SourceTextReader(network: SystemNetwork()).read(site.url)
    #expect(result.contains("Public signed-out text."))
    #expect(!result.contains("Private account text."))
  }

  @Test func aVideoReadsTheSitesCaptionsAndNeverDownloadsTheVideo() async throws {
    let network = SourceFixtureNetwork("")
    let mediaWorld = MediaWorld()
    defer { mediaWorld.place.remove() }
    try mediaWorld.install()
    mediaWorld.programs.site(
      Links.youtube,
      FakeSite(title: "Talk", subtitles: "WEBVTT\n\n00:00.100 --> 00:02.000\nWhat the speaker said.\n"))
    let media = mediaWorld.environment(transcriber: FakeTranscriber([])).media
    try await withSourceHost(network: network, media: media) { host, _, _, _ in
      let url = try #require(URL(string: Links.youtube))
      _ = try await host.run(SetBrowserLogin(.chrome))
      _ = try await host.run(
        HandOverBrowserCookies([
          BrowserCookie(
            domain: ".youtube.com", path: "/", name: "example-session", value: "test", secure: true, expires: nil)
        ]))
      #expect(try await host.run(ReadSource(url: url)) == "What the speaker said.")
      #expect(mediaWorld.programs.calls(with: "--cookies-from-browser").isEmpty)
      #expect(mediaWorld.programs.calls(with: "--cookies").isEmpty)
      #expect(mediaWorld.programs.calls(with: "--load-info-json").isEmpty)
      #expect(mediaWorld.programs.calls(with: "--write-subs").count == 1)
      #expect(mediaWorld.programs.calls(with: "--print").isEmpty)
      let noCaptions = try #require(URL(string: "https://www.youtube.com/watch?v=missing"))
      mediaWorld.programs.site(noCaptions.absoluteString, FakeSite(title: "Silent"))
      await #expect(throws: HostError.invalidRequest("This video has no transcript from site subtitles.")) {
        try await host.run(ReadSource(url: noCaptions))
      }
    }
  }

  private func requestForFile() throws -> LocalCall.Request {
    .command(name: ReadSource.name, body: try JSONEncoder().encode(ReadSource(url: fileURL())))
  }

  private func fileURL() throws -> URL {
    try #require(URL(string: "https://raw.githubusercontent.com/o/r/main/source.txt"))
  }

  private func withSourceHost(
    network: SourceFixtureNetwork, media: MediaEnvironment? = nil, seedExpired: Bool = false, agent: ManualAgent? = nil,
    _ body: (LocalHost, Place, TestWorld, SourceCache) async throws -> Void
  ) async throws {
    let place = Place(root: URL(filePath: "/tmp/loci-source-\(UUID())", directoryHint: .isDirectory))
    let cachePlace = Place()
    defer {
      place.remove()
      cachePlace.remove()
    }
    let world = TestWorld()
    let cache = SourceCache(root: cachePlace.root)
    if seedExpired {
      let past = Timestamp(millisecondsSince1970: world.now.millisecondsSince1970 - 14 * 86_400_000)
      let stage = try cache.stage(id: world.nextID(), at: past)
      try cache.publish(text: "Expired", for: .text(fileURL()), from: stage, at: past)
    }
    let environment = HostEnvironment(
      newID: { world.nextID() }, now: { world.now }, defaultRuntime: Runtime(provider: .pi), discard: .permanently,
      agents: { _ in agent }, ticks: world.environment.ticks,
      media: media
        ?? MediaEnvironment(
          support: place.root.appending(path: "support"), runner: FakePrograms(), network: network,
          transcriber: FakeTranscriber([]), searchPaths: [], readerLanguage: "en"),
      tool: AgentTool(folder: place.root, socket: DataFolder.socket(in: place.root)), sourceCache: cachePlace.root)
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    do {
      try await body(host, place, world, cache)
    } catch {
      await host.close()
      throw error
    }
    await host.close()
  }
}

private actor SourceFixtureNetwork: LociMedia.Network {
  private let body: Data
  private(set) var requests = 0

  init(_ text: String) { body = Data(text.utf8) }

  func data(for request: URLRequest) async throws(FetchError) -> (Data, HTTPURLResponse) {
    requests += 1
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else { throw FetchError(reason: "invalid test URL") }
    return (body, response)
  }

  func download(_ request: URLRequest, progress: @escaping @Sendable (Fraction?) -> Void) async throws(FetchError)
    -> URL
  {
    throw FetchError(reason: "unexpected download")
  }
}

private actor SourceFixtureGit: ProgramRunner {
  let commit: CommitID
  private(set) var fetches = 0

  init(commit: CommitID) { self.commit = commit }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError) -> ProgramResult
  {
    let args = call.arguments
    if args.contains("ls-remote") { return .init(status: 0, output: "\(commit)\tHEAD\n") }
    if args.contains("rev-parse") { return .init(status: 0, output: "\(commit)\n") }
    if args.contains("fetch") { fetches += 1 }
    if args.contains("init"), let path = args.last {
      let folder = URL(filePath: path, directoryHint: .isDirectory)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("A repo".utf8).write(to: folder.appending(path: "README.md"))
        try FileManager.default.createDirectory(at: folder.appending(path: ".git"), withIntermediateDirectories: false)
        try Data(commit.description.utf8).write(to: folder.appending(path: ".git/HEAD"))
      } catch {
        throw ProgramError(reason: error.localizedDescription)
      }
    }
    return .init(status: 0, output: "")
  }
}

private struct SourcePageSite {
  let url: URL
  let task: Task<Void, any Error>

  static func start(_ page: @escaping @Sendable (String) -> String) async throws -> Self {
    let listener = try NetworkListener(
      using: .parameters { TCP() }.localEndpoint(.hostPort(host: "127.0.0.1", port: .any)))
    let (ports, port) = AsyncStream<UInt16>.makeStream()
    listener.onStateUpdate { listener, state in
      if state == .ready, let opened = listener.port {
        port.yield(opened.rawValue)
        port.finish()
      }
      if case .failed = state { port.finish() }
    }
    let task = Task {
      defer { port.finish() }
      try await listener.run { connection in
        var request = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while request.range(of: terminator) == nil {
          let message = try await connection.receive(atMost: 8192)
          guard !message.content.isEmpty else { return }
          request.append(message.content)
        }
        let html = page(String(decoding: request, as: UTF8.self))
        let response =
          "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
          + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
        try await connection.send(Data(response.utf8), endOfStream: true)
      }
    }
    for await value in ports {
      let url = try #require(URL(string: "http://127.0.0.1:\(value)/source-\(UUID())"))
      return Self(url: url, task: task)
    }
    task.cancel()
    throw FetchError(reason: "The local source site did not start.")
  }

  func stop() { task.cancel() }
}
