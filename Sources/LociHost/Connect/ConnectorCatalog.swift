import Foundation
import LociConnect
import LociModel

/// The connectors that can be connected, in the order the page lists them: services over MCP, then websites,
/// then this Mac's calendars and reminders. MCP servers sign in the one way those without an app registered
/// ahead allow; GitHub uses the `gh` signed in on this Mac; websites use the built-in browser's sign-in.
enum ConnectorCatalog {
  struct Entry {
    let offer: ConnectorOffer
    /// The scope to ask for in place of the server's, when a narrower one only reads.
    var scope: String?
    /// For a website: what tells it is signed in.
    var site: Site?
  }

  /// A website the built-in browser can be signed into.
  struct Site {
    /// The domains its pages are on, the first its own.
    let domains: [String]
    /// The cookie it sets when someone signs in.
    let signedInCookie: String

    func covers(_ url: URL) -> Bool {
      guard let host = url.host()?.lowercased() else { return false }
      return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
  }

  static let entries: [Entry] = [
    mcp("notion", "Notion", "https://mcp.notion.com/mcp"),
    mcp("linear", "Linear", "https://mcp.linear.app/mcp", scope: "read"),
    Entry(offer: ConnectorOffer(id: ConnectorID("github"), name: "GitHub", kind: .github)),
    mcp("sentry", "Sentry", "https://mcp.sentry.dev/mcp"),
    mcp("atlassian", "Atlassian", "https://mcp.atlassian.com/v1/mcp"),
    site("x", "X", ["x.com", "twitter.com"], cookie: "auth_token", signIn: "https://x.com/i/flow/login"),
    site("v2ex", "V2EX", ["v2ex.com"], cookie: "A2", signIn: "https://www.v2ex.com/signin"),
    site(
      "xiaohongshu", "小红书", ["xiaohongshu.com"], cookie: "web_session", signIn: "https://www.xiaohongshu.com/explore"),
    site("bilibili", "哔哩哔哩", ["bilibili.com"], cookie: "SESSDATA", signIn: "https://passport.bilibili.com/login"),
    Entry(offer: ConnectorOffer(id: ConnectorID("calendar"), name: "日历", kind: .calendar)),
    Entry(offer: ConnectorOffer(id: ConnectorID("reminders"), name: "提醒事项", kind: .reminders)),
  ]

  /// GitHub's MCP address that offers only the tools that read.
  static let githubReadOnly = URL(string: "https://api.githubcopilot.com/mcp/readonly") ?? URL(filePath: "/")

  /// The tool beside GitHub's MCP tools that runs `gh` with arguments that only read.
  static let githubCommand = MCPTool(
    name: "gh",
    description: "Runs the gh signed in on this Mac with commands that only read, such as "
      + #"{"args": ["run", "view", "123", "--log", "-R", "owner/repo"]}; `loci connector call gh run view 123 …` "#
      + "says the same. pr, issue, repo, release, run, workflow, search and label can list and view; gh api only GET.",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "args": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
      ]),
      "required": .array([.string("args")]),
    ]), readOnly: true)

  /// What a website offers: reading one of its pages signed in.
  static func readTool(_ name: String, _ site: Site) -> MCPTool {
    MCPTool(
      name: "read",
      description: "Reads a page of \(name) signed in as the person, sending only GET: "
        + "{\"url\": \"https://\(site.domains[0])/…\"}. `loci read` on its pages does the same.",
      inputSchema: .object([
        "type": .string("object"), "properties": .object(["url": .object(["type": .string("string")])]),
        "required": .array([.string("url")]),
      ]), readOnly: true)
  }

  /// The app each of this Mac's own sources opens in.
  static func address(of kind: ConnectorOffer.Kind) -> URL? {
    switch kind {
    case .calendar: URL(string: "x-apple-calendar://")
    case .reminders: URL(string: "x-apple-reminderkit://")
    case .mcp, .github, .site: nil
    }
  }

  static func entry(_ id: ConnectorID) -> Entry? {
    entries.first { $0.offer.id == id }
  }

  /// The website a page is on, among those in the catalog.
  static func site(for url: URL) -> Entry? {
    entries.first { $0.site?.covers(url) == true }
  }

  static var sites: [Entry] { entries.filter { $0.site != nil } }

  private static func mcp(_ id: String, _ name: String, _ address: String, scope: String? = nil) -> Entry {
    Entry(
      offer: ConnectorOffer(id: ConnectorID(id), name: name, kind: .mcp(URL(string: address) ?? URL(filePath: "/"))),
      scope: scope)
  }

  private static func site(_ id: String, _ name: String, _ domains: [String], cookie: String, signIn: String) -> Entry {
    Entry(
      offer: ConnectorOffer(
        id: ConnectorID(id), name: name, kind: .site(signIn: URL(string: signIn) ?? URL(filePath: "/"))),
      site: Site(domains: domains, signedInCookie: cookie))
  }
}
