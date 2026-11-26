import Foundation
import LociModel
import LociRemote
import Testing

@testable import LociHost

/// R-S8: what this Mac kept of the other while an older version of Loci ran here can still be read offline once
/// it is updated, though its subscriptions now say what it can show.
@Suite(.timeLimit(.minutes(1)))
struct OfflineUpgradeTests {
  /// The conversation and the panel column as an older Mac asked for them.
  struct OlderConversationRequest: Codable {
    let conversation: ConversationRef
  }

  struct OlderPanelsRequest: Codable {
    let project: Project.ID?
  }

  @Test func whatAnOlderVersionKeptOfAConversationAndItsPanelsIsShownOfflineAfterUpdating() async throws {
    try await TwoMacs.with { macs in
      try await macs.pair()
      let studio = macs.studio.machine.id
      let conversation = try await macs.studio.local.conversation(.main)
      let column = try await macs.studio.local.panelColumn(of: .chat)
      await macs.studio.service.stop()
      #expect(await macs.connected(macs.laptop, to: macs.studio, link: .offline))
      let folder = macs.laptop.machineFolder
      try folder.cache(
        JSONEncoder().encode(Feed<Conversation>.value(conversation)), as: OneConversation.name,
        request: WireCodec.encode(OlderConversationRequest(conversation: .main)), on: studio)
      try folder.cache(
        JSONEncoder().encode(Feed<PanelColumn>.value(column)), as: WatchPanelColumn.name,
        request: WireCodec.encode(OlderPanelsRequest(project: nil)), on: studio)

      let remote = macs.laptop.service.open(studio)

      #expect(await first(remote.subscribe(OneConversation(.main))) { $0 == .value(conversation) } != nil)
      #expect(await first(remote.subscribe(WatchPanelColumn(of: .chat))) { $0 == .value(column) } != nil)
    }
  }
}
