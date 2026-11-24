import Foundation
import LociModel

extension FakeHost {
  func recall(_ command: Recall) async throws(HostError) -> [RecallHit] { [] }
  func wikiPage(_ name: String) async throws(HostError) -> WikiPage {
    do {
      return try (library ?? SampleLibrary()).wikiPage(name)
    } catch {
      throw .notFound(name)
    }
  }
  func forgetWikiLine(_ command: ForgetWikiLine) async throws(HostError) -> Done { Done() }
  func connectors() async throws(HostError) -> Connectors { sampleConnectors }
  func connectorCalls(limit: Int) async throws(HostError) -> [ConnectorCall] { [] }
  func connect(_ command: Connect) async throws(HostError) -> Authorization { .connected }
  func addMCPServer(_ command: AddMCPServer) async throws(HostError) -> Authorization { .connected }
  func cancelConnecting(_ command: CancelConnecting) async throws(HostError) -> Done { Done() }
  func disconnect(_ command: Disconnect) async throws(HostError) -> Done { Done() }
  func callConnector(_ command: CallConnector, from caller: ConnectorCall.Caller?) async throws(HostError) -> String {
    ""
  }
}

/// The connectors of the design, told against `SampleTimers.now`.
enum SampleConnectors {
  static let github = ConnectorID("github")
  static let notion = ConnectorID("notion")
  static let linear = ConnectorID("linear")
  static let sentry = ConnectorID("sentry")
  static let atlassian = ConnectorID("atlassian")

  static let x = ConnectorID("x")
  static let v2ex = ConnectorID("v2ex")
  static let xiaohongshu = ConnectorID("xiaohongshu")
  static let bilibili = ConnectorID("bilibili")
  static let calendar = ConnectorID("calendar")
  static let reminders = ConnectorID("reminders")

  static func offer(_ id: ConnectorID, _ name: String) -> ConnectorOffer {
    ConnectorOffer(id: id, name: name, kind: .mcp(URL(string: "https://mcp.\(id).com/mcp") ?? URL(filePath: "/")))
  }

  static func site(_ id: ConnectorID, _ name: String, _ domain: String) -> ConnectorOffer {
    ConnectorOffer(
      id: id, name: name, kind: .site(signIn: URL(string: "https://\(domain)/login") ?? URL(filePath: "/")))
  }

  static let sites = [
    site(x, "X", "x.com"), site(v2ex, "V2EX", "v2ex.com"), site(xiaohongshu, "小红书", "xiaohongshu.com"),
    site(bilibili, "哔哩哔哩", "bilibili.com"),
  ]

  static let local = [
    ConnectorOffer(id: calendar, name: "日历", kind: .calendar),
    ConnectorOffer(id: reminders, name: "提醒事项", kind: .reminders),
  ]

  /// The catalog, in the order the host lists it.
  static let offers =
    [
      offer(notion, "Notion"), offer(linear, "Linear"), offer(github, "GitHub"), offer(sentry, "Sentry"),
      offer(atlassian, "Atlassian"),
    ] + sites + local

  static func connector(_ id: ConnectorID, _ name: String, account: String?, _ status: Connector.Status = .ready)
    -> Connector
  {
    Connector(
      id: id, name: name, source: .mcp, server: URL(string: "https://mcp.\(id).com/mcp") ?? URL(filePath: "/"),
      account: account, status: status, tools: [], connectedAt: Timestamp(SampleTimers.now), readsToday: 0,
      lastUsed: nil)
  }

  /// A website the built-in browser is signed into, or this Mac's calendar: neither has an account to show.
  static func own(_ id: ConnectorID, _ name: String, _ source: ConnectorSource, at server: String) -> Connector {
    Connector(
      id: id, name: name, source: source, server: URL(string: server) ?? URL(filePath: "/"), account: nil,
      status: .ready, tools: [], connectedAt: Timestamp(SampleTimers.now), readsToday: 0, lastUsed: nil)
  }

  static let empty = Connectors(connected: [], available: offers, attempts: [:])

  /// GitHub reading, Notion's sign-in run out, X signed in in the built-in browser, the calendar allowed;
  /// Linear waiting for the browser, Sentry refused, and the other websites and reminders still to connect.
  static let design = Connectors(
    connected: [
      connector(github, "GitHub", account: "@Umupa"),
      connector(notion, "Notion", account: "sangmu.hhj@gmail.com", .needsReconnecting("the sign-in ran out")),
      own(x, "X", .site, at: "https://x.com"),
      own(calendar, "日历", .local, at: "x-apple-calendar://"),
    ],
    available: [offer(linear, "Linear"), offer(sentry, "Sentry"), offer(atlassian, "Atlassian")] + sites.dropFirst()
      + local.dropFirst(),
    attempts: [
      linear: .waiting(until: Timestamp(SampleTimers.now.addingTimeInterval(460))),
      sentry: .failed("Sentry refused the sign-in"),
    ])

  /// An address the person added, whose server says no account.
  static let added = Connectors(
    connected: [
      connector(github, "GitHub", account: "@Umupa"),
      Connector(
        id: ConnectorID("mcp-mcp.stripe.com"), name: "mcp.stripe.com", source: .mcp,
        server: URL(string: "https://mcp.stripe.com") ?? URL(filePath: "/"), account: nil, status: .ready, tools: [],
        connectedAt: Timestamp(SampleTimers.now), readsToday: 0, lastUsed: nil),
    ],
    available: [offer(notion, "Notion"), offer(linear, "Linear")], attempts: [:])
}
