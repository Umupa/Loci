import Testing

@testable import LociModel

struct ConnectorSitesTests {
  @Test(arguments: [
    ("linear.app", "linear"), ("https://linear.app/team/issue/ABC-1", "linear"), ("www.sentry.io", "sentry"),
    ("acme.atlassian.net", "atlassian"), ("twitter.com", "x"), ("https://www.bilibili.com/video/BV1", "bilibili"),
    ("v2ex", "v2ex"), ("calendar", "calendar"),
  ])
  func aSiteOrAConnectorsIdNamesTheConnector(site: String, id: String) {
    #expect(ConnectorSites.connector(for: site) == ConnectorID(id))
  }

  @Test(arguments: ["openai.com", "news.ycombinator.com", "notlinear.app", ""])
  func aSiteNoConnectorIsOnNamesNone(site: String) {
    #expect(ConnectorSites.connector(for: site) == nil)
  }

  @Test func aConnectorsOwnDomainComesFirst() {
    #expect(ConnectorSites.domains(of: ConnectorID("x")) == ["x.com", "twitter.com"])
    #expect(ConnectorSites.domains(of: ConnectorID("calendar")).isEmpty)
  }
}
