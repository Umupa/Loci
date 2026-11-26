import Foundation
import LociModel

extension FakeHost {
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done { Done() }
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done { Done() }
  func startOver(_ command: StartOver) async throws(HostError) -> Done { Done() }

  func conversation(_ conversation: ConversationRef) async throws(HostError) -> Conversation {
    let empty = Conversation(ref: conversation, entries: [], turn: nil)
    switch conversation {
    case .main:
      if let chat { return chat }
      if let library { return library.mainConversation(working: working) }
      return (try? sample.chat()) ?? empty
    case .project:
      guard let chat = try? sample.chat() else { return empty }
      return Conversation(ref: conversation, entries: Array(chat.entries.suffix(4)), turn: nil)
    case .course:
      if let supplied = courses?.conversation, supplied.ref == conversation { return supplied }
      return empty
    case .item(let item):
      if let library { return (try? library.conversation(on: item)) ?? empty }
      return item == sample.borg.id ? (try? sample.conversation()) ?? empty : empty
    }
  }

  func companionName() async throws(HostError) -> String { "小满" }
  func renameCompanion(_ command: RenameCompanion) async throws(HostError) -> Done { Done() }

  func lociStatus() async -> LociStatus {
    LociStatus(work: working ? .answering(library?.mainConversation(working: true).turn?.latestTool) : nil)
  }

  func lociPage() async throws(HostError) -> LociPage {
    do {
      let page = try (library ?? SampleLibrary()).lociPage
      guard !remembers else { return page }
      return LociPage(
        soul: page.soul, memory: [], profile: [], today: DayNotes(day: page.today.day, notes: []),
        diaries: page.diaries, together: page.together, feeling: page.feeling)
    } catch {
      throw .storage(String(describing: error))
    }
  }

  func diary(of day: Day) async throws(HostError) -> Diary {
    do {
      return try (library ?? SampleLibrary()).diary(of: day)
    } catch {
      throw .notFound(day.description)
    }
  }

  func saveSoul(_ command: SaveSoul) async throws(HostError) -> Soul { Soul(core: command.core, traits: []) }
  func forget(_ command: Forget) async throws(HostError) -> Done { Done() }
  func avatar() async throws(HostError) -> Avatar? { avatar }
  func setAvatar(_ command: SetAvatar) async throws(HostError) -> Done { Done() }
  func resetAvatar() async throws(HostError) -> Done { Done() }
}
