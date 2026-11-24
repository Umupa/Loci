import Foundation
import LociConnect
import LociModel
import LociStore

/// The connectors: connecting them in the browser, keeping their credentials in the keychain, and making
/// the companion's calls with them. The companion never holds a credential: the app adds it to each call.
actor ConnectorKeeper {
  let database: StoreDatabase
  let environment: HostEnvironment
  let follower: Follower
  var attempts: [ConnectorID: Attempt] = [:]
  var clients: [ConnectorID: MCPClient] = [:]

  /// A connection under way, and what to stop when it is given up.
  struct Attempt {
    var state: ConnectAttempt
    var work: Task<Void, Never>?
    var wait: (any CallbackWait)?
  }

  init(database: StoreDatabase, environment: HostEnvironment, follower: Follower) {
    self.database = database
    self.environment = environment
    self.follower = follower
  }

  var connect: ConnectEnvironment { environment.connect }
  var oauth: OAuth { OAuth(http: connect.http, randomBytes: connect.randomBytes) }

  func connectors() throws(HostError) -> Connectors {
    let records = try attempt { try database.connectorRecords() }
    let today = Day(containing: environment.now(), in: environment.timeZone).start(in: environment.timeZone)
    let calls = (try? database.connectorCalls(since: today)) ?? []
    let lastUsed = ((try? database.connectorCalls(limit: 500)) ?? []).reduce(into: [ConnectorID: Timestamp]()) {
      $0[$1.connector] = max($0[$1.connector] ?? $1.at, $1.at)
    }
    let connected = records.map { record in
      Connector(
        id: record.id, name: record.name, source: record.kind.source, server: record.server, account: record.account,
        status: record.status,
        tools: record.tools.filter { $0.readOnly == true }.map {
          ConnectorTool(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
        },
        connectedAt: record.connectedAt,
        readsToday: calls.count { $0.connector == record.id && $0.outcome == .read }, lastUsed: lastUsed[record.id])
    }
    let ids = Set(records.map(\.id))
    return Connectors(
      connected: connected, available: ConnectorCatalog.entries.map(\.offer).filter { !ids.contains($0.id) },
      attempts: attempts.mapValues(\.state))
  }

  /// Connects a connector from the catalog, or again one that was connected.
  func connect(_ id: ConnectorID) async throws(HostError) -> Authorization {
    if let entry = ConnectorCatalog.entry(id) { return try await connect(entry.offer, scope: entry.scope) }
    guard let record = try attempt({ try database.connectorRecord(id) }) else { throw .notFound(id.rawValue) }
    return try await connect(ConnectorOffer(id: id, name: record.name, kind: record.kind), scope: nil)
  }

  /// Connects an MCP address; one connected before keeps its id.
  func add(_ address: URL) async throws(HostError) -> Authorization {
    guard address.scheme == "https" || address.host() == "127.0.0.1" || address.host() == "localhost",
      let host = address.host(), !host.isEmpty
    else { throw .invalidRequest("An MCP address starts with https://") }
    let records = try attempt { try database.connectorRecords() }
    if let known = records.first(where: { $0.server == address }) { return try await connect(known.id) }
    let base = "mcp-" + host.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    let taken = Set(records.map(\.id.rawValue) + ConnectorCatalog.entries.map(\.offer.id.rawValue))
    let id = ([base] + (2...99).map { "\(base)-\($0)" }).first { !taken.contains($0) } ?? base
    return try await connect(ConnectorOffer(id: ConnectorID(id), name: host, kind: .mcp(address)), scope: nil)
  }

  func cancel(_ id: ConnectorID) async {
    guard let going = attempts.removeValue(forKey: id) else { return }
    going.work?.cancel()
    await going.wait?.close()
    await follower.follow([.connectors])
  }

  func disconnect(_ id: ConnectorID) async throws(HostError) {
    await cancel(id)
    guard try attempt({ try database.connectorRecord(id) }) != nil else { throw .notFound(id.rawValue) }
    if let vault = connect.vault {
      do throws(KeyVaultError) {
        try vault.setSecret(nil, for: id)
      } catch {
        throw .storage("the keychain would not let go of the credentials (\(error.status))")
      }
    }
    let record = try attempt { try database.connectorRecord(id) }
    if case .site? = record?.kind { try attempt { try database.setAside(id, true) } }
    try attempt { try database.removeConnector(id) }
    clients[id] = nil
    await follower.follow([.connectors])
  }

  func close() async {
    for id in Array(attempts.keys) { await cancel(id) }
  }

  private func connect(_ offer: ConnectorOffer, scope: String?) async throws(HostError) -> Authorization {
    await cancel(offer.id)
    do throws(ConnectError) {
      switch offer.kind {
      case .site(let signIn):
        return try await connectSite(offer, signIn: signIn)
      case .calendar, .reminders:
        return try await connectLocal(offer)
      case .github:
        guard let login = await connect.githubLogin() else {
          throw .needsReconnecting("gh is not signed in on this Mac; run `gh auth login` in Terminal first")
        }
        let tools = try await client(offer.id, ConnectorCatalog.githubReadOnly).tools(token: login.token)
        try save(offer, server: ConnectorCatalog.githubReadOnly, account: login.account, tools: tools, signedIn: false)
        return .connected
      case .mcp(let server):
        switch try await oauth.discover(server, scope: scope) {
        case .open:
          let tools = try await client(offer.id, server).tools(token: nil)
          try save(offer, server: server, account: nil, tools: tools, signedIn: false)
          return .connected
        case .signIn(let discovery):
          guard connect.vault != nil else { throw .unsupported("this Loci has no keychain to keep a sign-in in") }
          let wait = try await connect.receiver.open(for: offer.name)
          let pending: PendingAuthorization
          do throws(ConnectError) {
            pending = oauth.authorize(try await oauth.register(discovery, redirect: wait.redirect))
          } catch {
            await wait.close()
            throw error
          }
          let until = Timestamp(
            millisecondsSince1970: environment.now().millisecondsSince1970
              + connect.patience.components.seconds * 1000)
          attempts[offer.id] = Attempt(state: .waiting(until: until), work: nil, wait: wait)
          attempts[offer.id]?.work = Task { await self.finish(offer, pending, wait) }
          await follower.follow([.connectors])
          return .open(pending.url)
        }
      }
    } catch {
      attempts[offer.id] = Attempt(state: .failed(error.reason))
      await follower.follow([.connectors])
      throw .invalidRequest(error.reason)
    }
  }

  /// Waits for the browser, then signs in and keeps the credentials, tells the browser what came of it, and lets
  /// the app know the browser came back. Given up after `patience`.
  private func finish(_ offer: ConnectorOffer, _ pending: PendingAuthorization, _ wait: any CallbackWait) async {
    let outcome: ConnectAttempt?
    var answer = SignInOutcome.failed
    var returned = false
    do throws(ConnectError) {
      let callback = try await firstOf(wait, within: connect.patience)
      returned = true
      if Self.refused(callback) { answer = .declined }
      let credential = try await oauth.exchange(try pending.code(from: callback), now: environment.now())
      let server = pending.registration.discovery.resource.mcp
      clients[offer.id] = nil
      let tools = try await client(offer.id, server).tools(token: credential.accessToken)
      try keep(credential, for: offer.id)
      try save(offer, server: server, account: credential.account, tools: tools, signedIn: true)
      answer = .connected
      outcome = nil
    } catch {
      outcome = .failed(error.reason)
    }
    await wait.answer(answer)
    await wait.close()
    guard !Task.isCancelled, attempts[offer.id] != nil else { return }
    attempts[offer.id] = outcome.map { Attempt(state: $0) }
    await follower.follow([.connectors])
    if returned { await connect.browserReturned(offer.id) }
  }

  /// Whether the person refused on the service's page.
  private static func refused(_ callback: URL) -> Bool {
    URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?
      .contains { $0.name == "error" && $0.value == "access_denied" } == true
  }

  /// The callback, or a failure once `limit` has passed.
  private func firstOf(_ wait: any CallbackWait, within limit: Duration) async throws(ConnectError) -> URL {
    let sleep = environment.wait
    let result = await withTaskGroup(of: Result<URL, ConnectError>?.self) { group in
      group.addTask {
        do throws(ConnectError) {
          return .success(try await wait.callback())
        } catch {
          return .failure(error)
        }
      }
      group.addTask {
        await sleep(limit)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
    guard let result else {
      throw .callback("the browser did not come back in \(limit.components.seconds / 60) minutes")
    }
    return try result.get()
  }

  func client(_ id: ConnectorID, _ server: URL) -> MCPClient {
    if let client = clients[id], client.server == server { return client }
    let client = MCPClient(server: server, http: connect.http)
    clients[id] = client
    return client
  }

  func keep(_ credential: MCPCredential, for id: ConnectorID) throws(ConnectError) {
    guard let vault = connect.vault else { throw .unsupported("this Loci has no keychain to keep a sign-in in") }
    do {
      try vault.setSecret(try JSONEncoder().encode(credential), for: id)
    } catch {
      throw .server("the keychain would not keep the sign-in")
    }
  }

  func save(
    _ offer: ConnectorOffer, server: URL, account: String?, tools: [MCPTool], signedIn: Bool
  ) throws(ConnectError) {
    let record = ConnectorRecord(
      id: offer.id, name: offer.name, kind: offer.kind, server: server, account: account, status: .ready,
      connectedAt: environment.now(), tools: Self.kept(tools, for: offer.kind), signedIn: signedIn)
    do {
      try database.saveConnector(record)
    } catch {
      throw .server("could not keep the connector: \(error)")
    }
  }

  /// The tools kept for a connector: GitHub's MCP tools come with the `gh` that reads.
  static func kept(_ tools: [MCPTool], for kind: ConnectorOffer.Kind) -> [ConnectorRecord.Tool] {
    (kind == .github ? tools + [ConnectorCatalog.githubCommand] : tools).map(stored)
  }

  static func stored(_ tool: MCPTool) -> ConnectorRecord.Tool {
    ConnectorRecord.Tool(
      name: tool.name, description: tool.description, inputSchema: tool.inputSchema.text, readOnly: tool.readOnly)
  }
}
