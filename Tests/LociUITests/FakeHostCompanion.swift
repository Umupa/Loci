import LociModel

@testable import LociUI

extension FakeHost {
  func askCompanion(_ command: AskCompanion) async throws(HostError) -> Done { Done() }
  func stopCompanion(_ command: StopCompanion) async throws(HostError) -> Done { Done() }
  func startOverCompanion(_ command: StartOverCompanion) async throws(HostError) -> Done { Done() }

  func chooseCompanion(_ command: ChooseCompanion) async throws(HostError) -> ItemConversation {
    ItemConversation(item: command.item, companion: command.mentor, messages: [], turn: nil)
  }

  func itemConversation(on item: EntityID) async throws(HostError) -> ItemConversation {
    if let library, let conversation = try? library.conversation(on: item) { return conversation }
    return ItemConversation(item: item, companion: sample.mentors.first?.id, messages: [], turn: nil)
  }
}
