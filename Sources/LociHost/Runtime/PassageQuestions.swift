import Foundation
import LociAgents
import LociModel
import LociStore

/// Questions about passages, answered in a session of each mentor's own beside its conversation, so a
/// mentor busy writing a lesson still answers. One mentor answers one question at a time, in order.
actor PassageQuestions {
  private struct Asked {
    let id: EntityID
    let content: ContentRef
    var pending: PendingAnswer
  }

  private let context: RunContext
  private var asked: [Asked] = []
  private var sessions: [EntityID: any AgentSession] = [:]
  private var queues: [EntityID: Task<Void, Never>] = [:]
  /// Moves on when a mentor's questions are closed; work begun in an earlier epoch quits without a trace.
  private var epochs: [EntityID: Int] = [:]

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
    let id = context.environment.newID()
    asked.append(Asked(id: id, content: locator.content, pending: pending))
    await changed(locator.content)
    let prompt = Soul.question(question, about: locator, excerpt: excerpt)
    let before = queues[mentor.id]
    let epoch = epochs[mentor.id, default: 0]
    queues[mentor.id] = Task {
      await before?.value
      guard self.isCurrent(mentor.id, epoch) else { return }
      await self.answer(prompt, by: mentor, for: pending, on: locator.content, id: id, epoch: epoch)
    }
  }

  /// Ends the questions of one mentor, or of all: unanswered ones are dropped, queued ones never start,
  /// and the side session is closed. Returns once none of that work is left running.
  func close(_ mentor: EntityID? = nil) async {
    let leaving = mentor.map { Set([$0]) } ?? Set(queues.keys).union(sessions.keys).union(asked.map(\.pending.mentor))
    for id in leaving { epochs[id, default: 0] += 1 }
    let dropped = Set(asked.filter { leaving.contains($0.pending.mentor) }.map(\.content))
    asked.removeAll { leaving.contains($0.pending.mentor) }
    let work = leaving.compactMap { queues.removeValue(forKey: $0) }
    for id in leaving {
      await sessions.removeValue(forKey: id)?.close()
    }
    for task in work {
      task.cancel()
      await task.value
    }
    for content in dropped { await changed(content) }
  }

  private func isCurrent(_ mentor: EntityID, _ epoch: Int) -> Bool {
    epochs[mentor, default: 0] == epoch
  }

  private func answer(
    _ prompt: String, by mentor: Mentor, for pending: PendingAnswer, on content: ContentRef, id: EntityID,
    epoch: Int
  ) async {
    do throws(TurnFailure) {
      let session = try await session(of: mentor, epoch: epoch)
      let turn = try await TurnFailure.awaiting { () async throws(AgentError) in try await session.send(prompt) }
      var text = ""
      for await event in turn.events {
        guard isCurrent(mentor.id, epoch) else { return }
        switch event {
        case .text(let more):
          text += more
          update(id) { $0.answer = text }
          await changed(content)
        case .permission(let request):
          await session.answer(request.id, with: .dismissed)
        case .ended(.failed(let error)):
          await session.close()
          sessions[mentor.id] = nil
          throw TurnFailure(reason: error.explanation)
        case .ended(.interrupted):
          throw TurnFailure(reason: AgentError.provider("The question was stopped.").explanation)
        default:
          break
        }
      }
      guard isCurrent(mentor.id, epoch) else { return }
      try save(text, for: pending, on: content)
      asked.removeAll { $0.id == id }
      await context.follower.follow([.notes(content), .answers(content)])
    } catch {
      guard isCurrent(mentor.id, epoch) else { return }
      update(id) { $0.failure = error.reason }
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

  /// The mentor's side session. One that finishes opening after its mentor's questions were closed is
  /// closed again at once.
  private func session(of mentor: Mentor, epoch: Int) async throws(TurnFailure) -> any AgentSession {
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
    guard isCurrent(mentor.id, epoch) else {
      await session.close()
      throw TurnFailure(reason: "The mentor was deleted.")
    }
    sessions[mentor.id] = session
    return session
  }

  private func update(_ id: EntityID, _ change: (inout Draft) -> Void) {
    guard
      let index = asked.firstIndex(where: { $0.id == id })
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
