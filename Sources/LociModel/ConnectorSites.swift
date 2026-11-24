import Foundation

/// The websites each catalog connector is on, the first its own: where the catalog finds a website's sign-in,
/// and how a site a panel reads is known for a connector and marked with the connector's icon.
public enum ConnectorSites {
  private static let domains: [(ConnectorID, [String])] = [
    (ConnectorID("notion"), ["notion.so", "notion.site"]),
    (ConnectorID("linear"), ["linear.app"]),
    (ConnectorID("github"), ["github.com"]),
    (ConnectorID("sentry"), ["sentry.io", "sentry.dev"]),
    (ConnectorID("atlassian"), ["atlassian.net", "atlassian.com"]),
    (ConnectorID("x"), ["x.com", "twitter.com"]),
    (ConnectorID("v2ex"), ["v2ex.com"]),
    (ConnectorID("xiaohongshu"), ["xiaohongshu.com"]),
    (ConnectorID("bilibili"), ["bilibili.com"]),
    (ConnectorID("calendar"), []),
    (ConnectorID("reminders"), []),
  ]

  /// The domains a connector's pages are on, the first its own; none for one that is not on the web.
  public static func domains(of id: ConnectorID) -> [String] {
    domains.first { $0.0 == id }?.1 ?? []
  }

  /// The connector a site belongs to: from a domain such as `www.linear.app` or one of its subdomains, a whole
  /// address, or the connector's id as a panel may name it.
  public static func connector(for site: String) -> ConnectorID? {
    let typed = site.trimmingCharacters(in: .whitespaces).lowercased()
    if let named = domains.first(where: { $0.0.rawValue == typed }) { return named.0 }
    let host = URL(string: typed)?.host() ?? typed
    return domains.first { _, domains in domains.contains { host == $0 || host.hasSuffix("." + $0) } }?.0
  }
}
