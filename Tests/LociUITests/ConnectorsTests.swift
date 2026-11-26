import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// CN-S1, CN-S2, CN-S7, CN-S8: the Connectors page, in ink and gray.
@MainActor
@Suite(.serialized, .onStage)
struct ConnectorsTests {
  @Test func aReplyWrittenAsAConnectorsLinkOpensThatConnector() {
    let answer = QuickAnswer("[重新连接 Notion](loci://connectors/notion)")

    #expect(answer.words == "重新连接 Notion")
    #expect(answer.place == .connector(ConnectorID("notion")))
    #expect(QuickAnswer("好的").place == nil)
    #expect(QuickAnswer("[看看](https://example.com)").place == nil)
  }

  @Test func aCustomMCPAddressHasNoBrandArtwork() {
    let id = ConnectorID("mcp-mcp.stripe.com")
    #expect(MarkArt.connector(id, in: .light) == nil)
    #expect(MarkArt.connector(id, in: .dark) == nil)
  }

  /// CN-S1, CN-S11, CN-S13: each offered service or app is recognizable by its own icon.
  @Test(arguments: SampleConnectors.offers.map(\.id))
  func everyBuiltInConnectorDisplaysAnImage(id: ConnectorID) {
    #expect(MarkArt.connector(id, in: .light)?.isValid == true)
    #expect(MarkArt.connector(id, in: .dark)?.isValid == true)
  }

  /// CN-S12: a website's sign-in page opens in the built-in browser; an OAuth one in the default browser.
  @Test func eachSignInPageOpensInTheBrowserItIsFor() {
    var outside: [URL] = []
    var inside: [URL] = []
    let site = URL(string: "https://www.v2ex.com/signin")!
    let oauth = URL(string: "https://mcp.notion.com/authorize")!
    for authorization in [Authorization.openInBuiltInBrowser(site), .open(oauth), .connected] {
      authorization.follow(inBrowser: { outside.append($0) }, inBuiltInBrowser: { inside.append($0) })
    }
    #expect(inside == [site] && outside == [oauth])
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connectorsPage(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-connectors", SampleConnectors.design, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connectorsPageEmpty(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-connectors-empty", SampleConnectors.empty, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connectorsPageWithAnAddedAddress(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-connectors-added", SampleConnectors.added, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connectorsPageFromAnotherMac(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-connectors-remote", SampleConnectors.design, appearance: appearance, away: "Mac mini")
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connectorsPageNarrow(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-connectors-narrow", SampleConnectors.design, appearance: appearance, width: 520)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func connectorsPageInEnglish(appearance: Snapshot.Appearance) async throws {
    try await shoot("loci-connectors-en", SampleConnectors.design, appearance: appearance, english: true)
  }

  private func shoot(
    _ name: String, _ connectors: Connectors, appearance: Snapshot.Appearance, away: String? = nil,
    english: Bool = false, width: CGFloat = 1036
  ) async throws {
    let view = HStack(spacing: 0) { LociScreen(tab: .connectors) }
      .lociHost(FakeHost(try Sample(problems: false), library: try SampleLibrary(), connectors: connectors))
      .environment(\.fixedNow, SampleTimers.now)
      .environment(\.machineChoice, away.map(Self.elsewhere))
    try await ScreenSnapshots.shoot(
      name, view, appearance: appearance, english: english, size: CGSize(width: width, height: 900))
  }

  /// Another Mac, reached and shown, named `name`.
  private static func elsewhere(_ name: String) -> MachineChoice {
    let here = Machine(id: MachineID(publicKey: Data([1])), name: "MacBook Air", model: .laptop)
    let there = Machine(id: MachineID(publicKey: Data([2])), name: name, model: .mini)
    return MachineChoice(
      roster: Roster(this: here, paired: []), shown: there, link: .connected, menuOpen: false, openMenu: {},
      addMac: {}, remove: { _ in }, acceptInvite: { _ in })
  }
}
