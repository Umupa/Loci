import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func askCompanion(_ command: AskCompanion) async throws(HostError) -> Done {
    let text = command.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw .invalidRequest("the message is empty") }
    try await checkCompanion(command.mentor, on: command.item)
    if let passage = command.passage, passage.locator.content != .item(command.item) {
      throw .invalidRequest("the passage is not in this item")
    }
    guard !(await mentors.isBusy(on: command.item)) else { throw .invalidRequest(MentorRun.busyOnItem) }
    try remember(command.mentor, on: command.item)
    guard let passage = command.passage else {
      try await mentors.ask(command.mentor, on: command.item, Prompt(text: text, purpose: .chat), saying: nil)
      return Done()
    }
    let quoted = QuotedPassage(
      locator: passage.locator, excerpt: passage.excerpt, note: try await note(on: passage).id)
    try await mentors.ask(
      command.mentor, on: command.item, Prompt(text: text, purpose: .chat, passage: quoted),
      saying: Soul.ask(text, about: passage))
    return Done()
  }

  public func stopCompanion(_ command: StopCompanion) async throws(HostError) -> Done {
    for run in await mentors.runs(on: command.item) { await run.stop() }
    return Done()
  }

  public func chooseCompanion(_ command: ChooseCompanion) async throws(HostError) -> ItemConversation {
    try await checkCompanion(command.mentor, on: command.item)
    try remember(command.mentor, on: command.item)
    await follow([.itemConversation(command.item)])
    return try await itemConversation(on: command.item)
  }

  /// The stored messages and the running turn are read separately, so a turn that was stored in between is
  /// shown once, from the store.
  public func itemConversation(on item: EntityID) async throws(HostError) -> ItemConversation {
    _ = try attempt { try store.item(item) }
    var running: CompanionTurn?
    var usage: [EntityID: ContextUsage] = [:]
    for run in await mentors.runs(on: item) {
      let live = await run.live
      if let turn = live.turn { running = CompanionTurn(mentor: run.mentor, turn: turn) }
      if let context = live.context { usage[run.mentor] = context }
    }
    let messages = try attempt { try database.messages(on: item) }
    if let first = running?.turn.messages.first, messages.contains(where: { $0.id == first.id }) { running = nil }
    let companion = try await companion(on: item)
    return ItemConversation(
      item: item, companion: companion, messages: messages, turn: running,
      context: companion.flatMap { usage[$0] })
  }

  /// The mentor chosen for the item, or else the one chosen last on any item, or else the first mentor;
  /// only a mentor that still exists.
  private func companion(on item: EntityID) async throws(HostError) -> EntityID? {
    let all = try await listMentors().map(\.id)
    if let chosen = try attempt({ try database.companion(on: item) }), all.contains(chosen) { return chosen }
    return all.first
  }

  private func checkCompanion(_ mentor: EntityID, on item: EntityID) async throws(HostError) {
    _ = try attempt { try store.item(item) }
    _ = try attempt { try store.mentor(mentor) }
  }

  private func remember(_ mentor: EntityID, on item: EntityID) throws(HostError) {
    try attempt { try database.choose(companion: mentor, on: item, at: environment.now()) }
  }
}
