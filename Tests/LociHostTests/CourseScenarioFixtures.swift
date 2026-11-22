import Foundation
import LociAgents
import LociModel
import LociStore
import Testing

@testable import LociHost

extension CourseScenarioTests {
  func idle(_ course: EntityID, on host: LocalHost) async throws {
    _ = try #require(await value(host.subscribe(WatchCourse(course)), within: .seconds(5)) { $0.activity == .idle })
  }

  func withCourseHost(
    _ body: (LocalHost, Place, ManualAgent) async throws -> Void
  ) async throws {
    let place = Place()
    defer { place.remove() }
    let world = TestWorld()
    let agent = ManualAgent(provider: .codex)
    let environment = world.environment(
      running: { provider in provider == .codex ? agent : nil },
      runtime: Runtime(provider: .codex))
    let host = try await LocalHost.start(root: place.root, database: place.database, environment: environment)
    do {
      try await body(host, place, agent)
    } catch {
      await host.close()
      throw error
    }
    await host.close()
  }

  func tag(for course: EntityID, on agent: ManualAgent) async throws -> LocalSession {
    let tag = await agent.opened.reversed().compactMap {
      $0.environment[LocalCall.sessionVariable].flatMap(LocalSession.init(tag:))
    }
    .first { $0.conversation == .course(course) }
    return try #require(tag)
  }

  func turn(for course: EntityID, on agent: ManualAgent, number: Int = 1) async throws -> ManualSession {
    for _ in 0..<200 {
      let opened = await agent.opened
      let sessions = await agent.sessions
      if let index = opened.firstIndex(where: {
        $0.environment[LocalCall.sessionVariable].flatMap(LocalSession.init(tag:))?.conversation == .course(course)
      }), sessions.indices.contains(index), await sessions[index].prompts.count >= number {
        return sessions[index]
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw HostError.notFound("course turn \(number)")
  }

  private actor Reply {
    var value: LocalReply?
    func set(_ value: LocalReply) { self.value = value }
  }

  func answer(_ request: CourseToolRequest, from session: LocalSession?, on host: LocalHost) async
    -> LocalReply?
  {
    let reply = Reply()
    await ToolGateway.answer(LocalCall(session: session, request: .course(request)), on: host) { await reply.set($0) }
    return await reply.value
  }

  func run(_ request: CourseToolRequest, in tag: LocalSession, on host: LocalHost) async throws {
    let reply = try #require(await answer(request, from: tag, on: host))
    if case .failed(let error) = reply { throw error }
  }

  func question(confirmation: Bool = false) throws -> CourseQuestion.Draft {
    try CourseQuestion.Draft(
      question: confirmation ? "Did I get it right?" : "Why learn this?",
      options: [
        CourseQuestion.Option(title: confirmation ? "Yes" : "For work", detail: "Focus on the system"),
        CourseQuestion.Option(title: confirmation ? "Revise" : "For interviews", detail: "Focus on explaining it"),
      ], multiple: false, purpose: confirmation ? .confirmation : .followUp(field: .purpose))
  }

  func lessons() throws -> [Lesson] {
    try (1...5).map { number in
      try Lesson(id: #require(Lesson.ID("claim-\(number)")), title: "Claim \(number)")
    }
  }

  func seed(stage: CourseStage, in place: Place, id: EntityID) throws -> Course {
    var course = try Course(id: id, topic: "Raft", createdAt: TestWorld.instant)
    let questionID = EntityID()
    try course.ask(CourseQuestion(id: questionID, draft: question(confirmation: true)))
    _ = try course.answer(question: questionID, with: .option(0))
    try course.updateGoal(CourseGoal(subtitle: "A quorum holds", length: "Five lessons"))
    try course.markGoalReady()
    try course.beginSources()
    let url = try #require(URL(string: "https://example.org/raft.pdf"))
    _ = try course.addSource(CourseSource.Draft(url: url), id: EntityID())
    if stage == .writing {
      try course.beginWriting()
      try course.replacePlan(lessons(), keepingWritten: [])
    }
    try place.store.createCourse(course)
    return course
  }
}
