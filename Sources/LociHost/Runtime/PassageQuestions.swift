import Foundation
import LociAgents
import LociModel
import LociStore

/// Questions about passages, answered in a session of each mentor's own beside its conversation, so a
/// mentor busy writing a lesson still answers. One mentor answers one question at a time, in order.
actor PassageQuestions {
  private struct Asked {
    let content: ContentRef
    var pending: PendingAnswer
  }

  private let context: RunContext
  private var asked: [Asked] = []
  private var sessions: [EntityID: any AgentSession] = [:]
  private var queues: [EntityID: Task<Void, Never>] = [:]

  init(context: RunContext) {
    self.context = context
  }

  func pending(on content: ContentRef) -> [PendingAnswer] {
    asked.filter { $0.content == content }.map(\.pending)
  }

  /// Queues the question and returns at once. The answer goes into the note when it is complete.
  func ask(_ question: String, of mentor: Mentor, about locator: Locator, excerpt: String?, note: EntityID) async {
    let pending = PendingAnswer(
      note: note, mentor: mentor.id, question: question, askedAt: context.environment.now(), answer: "",
      failure: nil)
    asked.append(Asked(content: locator.content, pending: pending))
    await changed(locator.content)
    let prompt = Soul.question(question, about: locator, excerpt: excerpt)
    let before = queues[mentor.id]
    queues[mentor.id] = Task {
      await before?.value
      await self.answer(prompt, by: mentor, for: pending, on: locator.content)
    }
  }

  func close(_ mentor: EntityID? = nil) async {
    let leaving = sessions.filter { mentor == nil || $0.key == mentor }
    for (id, session) in leaving {
      queues[id]?.cancel()
      await session.close()
      sessions[id] = nil
    }
  }

  private func answer(_ prompt: String, by mentor: Mentor, for pending: PendingAnswer, on content: ContentRef) async {
    do throws(TurnFailure) {
      let session = try await session(of: mentor)
      let turn = try await TurnFailure.awaiting { () async throws(AgentError) in try await session.send(prompt) }
      var text = ""
      for await event in turn.events {
        switch event {
        case .text(let more):
          text += more
          update(pending) { $0.answer = text }
          await changed(content)
        case .permission(let request):
          await session.answer(request.id, with: .dismissed)
        case .ended(.failed(let error)):
          sessions[mentor.id] = nil
          throw TurnFailure(reason: error.explanation)
        case .ended(.interrupted):
          throw TurnFailure(reason: AgentError.provider("The question was stopped.").explanation)
        default:
          break
        }
      }
      try save(text, for: pending, on: content)
      asked.removeAll { $0.pending.note == pending.note && $0.pending.askedAt == pending.askedAt }
      await context.follower.follow([.notes(content), .answers(content)])
    } catch {
      update(pending) { $0.failure = error.reason }
      await changed(content)
    }
  }

  private func save(_ answer: String, for pending: PendingAnswer, on content: ContentRef) throws(TurnFailure) {
    let store = context.store
    let now = context.environment.now()
    try TurnFailure.from { () throws(HostError) in
      try attempt {
        guard let note = store.notes(on: content).value.first(where: { $0.id == pending.note }) else {
          throw HostError.notFound(pending.note.description)
        }
        let exchange = try Note.Exchange(
          question: pending.question, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
          mentor: pending.mentor, askedAt: pending.askedAt)
        let saved = try Note(
          id: note.id, locator: note.locator, excerpt: note.excerpt, thought: note.thought,
          exchanges: note.exchanges + [exchange], savedAt: now)
        try store.append(.saved(saved), on: content)
      }
    }
  }

  private func session(of mentor: Mentor) async throws(TurnFailure) -> any AgentSession {
    if let session = sessions[mentor.id] { return session }
    guard let driver = await context.environment.agents(mentor.provider) else {
      throw TurnFailure(reason: "\(mentor.provider.rawValue) is not installed on this Mac.")
    }
    let store = context.store
    let folder = try TurnFailure.from { () throws(HostError) in
      let soul = try Soul.text(for: mentor)
      return try attempt {
        try store.installSoul(soul, for: mentor.id)
        return try store.workingFolder(of: mentor.id)
      }
    }
    let configuration = SessionConfiguration(
      workingDirectory: folder, model: mentor.model, permission: mentor.permission)
    let session = try await TurnFailure.awaiting { () async throws(AgentError) in try await driver.open(configuration) }
    sessions[mentor.id] = session
    return session
  }

  private func update(_ pending: PendingAnswer, _ change: (inout Draft) -> Void) {
    guard
      let index = asked.firstIndex(where: { $0.pending.note == pending.note && $0.pending.askedAt == pending.askedAt })
    else { return }
    let current = asked[index].pending
    var draft = Draft(answer: current.answer, failure: current.failure)
    change(&draft)
    asked[index].pending = PendingAnswer(
      note: current.note, mentor: current.mentor, question: current.question, askedAt: current.askedAt,
      answer: draft.answer, failure: draft.failure)
  }

  private struct Draft {
    var answer: String
    var failure: String?
  }

  private func changed(_ content: ContentRef) async {
    await context.follower.follow([.answers(content)])
  }
}
