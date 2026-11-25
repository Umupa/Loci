import Foundation
import LociAgents
import LociConnect
import LociMedia
import LociModel
import LociStore

/// The connectors that are not MCP servers: websites signed into in the built-in browser, this Mac's
/// calendars and reminders, and the `gh` beside GitHub's MCP tools. Each only reads, and every call is
/// recorded and marked as content from outside, as MCP calls are.
extension ConnectorKeeper {
  /// Follows the built-in browser's sign-ins for as long as the host runs.
  func watchSites() async {
    let changes = connect.sites.changes()
    await noticeSites()
    for await _ in changes { await noticeSites() }
  }

  /// Puts each website the built-in browser is signed into among the connected, unless the person
  /// disconnected it; one signed out of asks to be reconnected; one being connected is done.
  func noticeSites() async {
    let sites = ConnectorCatalog.sites
    let cookies = await connect.sites.cookies(on: sites.flatMap { $0.site?.domains ?? [] })
    let setAside = (try? database.setAsideConnectors()) ?? []
    let now = environment.now().date
    var changed = false
    for entry in sites {
      guard let site = entry.site else { continue }
      let id = entry.offer.id
      let signedIn = cookies.contains { cookie in
        cookie.name == site.signedInCookie && site.domains.contains { cookie.belongs(to: $0) }
          && (cookie.expires.map { $0 > now } ?? true)
      }
      let record = (try? database.connectorRecord(id)) ?? nil
      switch (record, signedIn) {
      case (nil, true) where !setAside.contains(id) || attempts[id] != nil:
        try? database.setAside(id, false)
        try? saveSite(entry.offer, site)
        attempts[id] = nil
        changed = true
      case (let record?, false) where record.status == .ready:
        try? database.saveConnector(record.with(status: .needsReconnecting(signedOut(entry.offer.name))))
        changed = true
      case (let record?, true) where record.status != .ready:
        try? database.saveConnector(record.with(status: .ready))
        attempts[id] = nil
        changed = true
      default: continue
      }
    }
    if changed { await follower.follow([.connectors]) }
  }

  /// A website: connected at once when the built-in browser is signed in already, otherwise its sign-in
  /// page opens in the built-in browser and the connection waits for the sign-in to arrive.
  func connectSite(_ offer: ConnectorOffer, signIn: URL) async throws(ConnectError) -> Authorization {
    try? database.setAside(offer.id, false)
    await noticeSites()
    if let record = (try? database.connectorRecord(offer.id)) ?? nil, record.status == .ready { return .connected }
    let until = Timestamp(
      millisecondsSince1970: environment.now().millisecondsSince1970 + connect.patience.components.seconds * 1000)
    let patience = connect.patience
    let sleep = environment.wait
    attempts[offer.id] = Attempt(state: .waiting(until: until), work: nil, wait: nil)
    attempts[offer.id]?.work = Task {
      await sleep(patience)
      await self.giveUp(offer)
    }
    await follower.follow([.connectors])
    return .openInBuiltInBrowser(signIn)
  }

  private func giveUp(_ offer: ConnectorOffer) async {
    guard !Task.isCancelled, case .waiting? = attempts[offer.id]?.state else { return }
    attempts[offer.id] = Attempt(
      state: .failed("No sign-in to \(offer.name) arrived in the built-in browser in time."), work: nil, wait: nil)
    await follower.follow([.connectors])
  }

  /// The calendars or reminders: macOS asks the person the first time.
  func connectLocal(_ offer: ConnectorOffer) async throws(ConnectError) -> Authorization {
    let kind = Self.personalKind(offer.kind)
    guard await connect.personal.requestAccess(to: kind) else {
      throw .needsReconnecting(Self.notAllowed(offer.name))
    }
    try save(
      offer, server: ConnectorCatalog.address(of: offer.kind) ?? URL(filePath: "/"), account: nil,
      tools: PersonalTools.tools(for: kind), signedIn: false)
    await follower.follow([.connectors])
    return .connected
  }

  /// Answers a call to a connector that is not an MCP server, or the `gh` of GitHub; `nil` for one an MCP
  /// server answers.
  func callOwn(
    _ command: CallConnector, arguments: JSONValue, record: ConnectorRecord, by caller: ConnectorCall.Caller
  ) async throws(HostError) -> String? {
    switch record.kind {
    case .mcp: return nil
    case .github:
      guard command.tool == "gh" else { return nil }
      return try await callGitHub(command, arguments: arguments, by: caller)
    case .site:
      guard command.tool == "read", let url = arguments["url"]?.string.flatMap(URL.init(string:)) else {
        try await refuse(command, caller, "\(record.name) reads pages: call it with read {\"url\": \"…\"}.")
      }
      return try await readSite(url, record: record, by: caller, command: command)
    case .calendar, .reminders:
      let kind = Self.personalKind(record.kind)
      guard await connect.personal.access(to: kind) == .granted else {
        await mark(record, .needsReconnecting(Self.notAllowed(record.name)))
        try await refuse(command, caller, Self.reconnect(record, Self.notAllowed(record.name)))
      }
      let text: String
      do throws(ConnectError) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = environment.timeZone
        text = try await PersonalTools.run(
          command.tool, arguments: arguments, kind: kind, on: connect.personal, now: environment.now().date,
          calendar: calendar)
      } catch {
        try await refuse(
          command, caller, "\(error.reason). Run `loci connector list \(record.id)` to see what it can read.")
      }
      await log(command, caller, .read)
      return Self.answer(caller, text, from: record.id.rawValue, tool: command.tool)
    }
  }

  /// The connected website a page is on, if the companion should read it signed in.
  func signedInSite(for url: URL) -> ConnectorRecord? {
    guard let entry = ConnectorCatalog.site(for: url),
      let record = (try? database.connectorRecord(entry.offer.id)) ?? nil, record.status == .ready
    else { return nil }
    return record
  }

  /// Reads a page of a connected website with its sign-in, sending only GET and never from a cache, and
  /// records the call.
  func readSite(
    _ url: URL, record: ConnectorRecord, by caller: ConnectorCall.Caller, command: CallConnector? = nil
  ) async throws(HostError) -> String {
    let call = command ?? CallConnector(record.id, tool: "read")
    guard ConnectorCatalog.entry(record.id)?.site?.covers(url) == true, url.isWebLink else {
      try await refuse(call, caller, "\(url.absoluteString) is not a page of \(record.name).")
    }
    if case .needsReconnecting(let why) = record.status { try await refuse(call, caller, Self.reconnect(record, why)) }
    let text: String
    do throws(FetchError) {
      text = try await connect.sites.read(url)
    } catch {
      await log(call, caller, .failed(error.reason))
      throw .invalidRequest("\(record.name) could not be read: \(error.reason)")
    }
    await log(call, caller, .read)
    return Self.answer(caller, text, from: record.id.rawValue, tool: "read")
  }

  private func callGitHub(_ command: CallConnector, arguments: JSONValue, by caller: ConnectorCall.Caller)
    async throws(HostError) -> String
  {
    guard let given = arguments["args"]?.array else {
      try await refuse(command, caller, #"gh takes its words as {"args": ["pr", "view", "12"]}."#)
    }
    let words = given.compactMap(\.string)
    switch await connect.githubRead(words) {
    case .output(let text):
      await log(command, caller, .read)
      return Self.answer(caller, text, from: "github", tool: "gh " + words.prefix(2).joined(separator: " "))
    case .refused(let why):
      try await refuse(command, caller, why)
    case .failed(let why):
      await log(command, caller, .failed(why))
      throw .invalidRequest("gh could not read: \(why)")
    }
  }

  private func refuse(_ command: CallConnector, _ caller: ConnectorCall.Caller, _ reason: String)
    async throws(HostError) -> Never
  {
    await log(command, caller, .refused(reason))
    throw .invalidRequest(reason)
  }

  private func saveSite(_ offer: ConnectorOffer, _ site: ConnectorCatalog.Site) throws(ConnectError) {
    let home = URL(string: "https://\(site.domains[0])") ?? URL(filePath: "/")
    try save(offer, server: home, account: nil, tools: [ConnectorCatalog.readTool(offer.name, site)], signedIn: false)
  }

  private func signedOut(_ name: String) -> String {
    "signed out of \(name) in the built-in browser"
  }

  static func notAllowed(_ name: String) -> String {
    "macOS does not let Loci read \(name); allow it in System Settings › Privacy & Security"
  }

  static func personalKind(_ kind: ConnectorOffer.Kind) -> PersonalKind {
    kind == .reminders ? .reminders : .events
  }
}
