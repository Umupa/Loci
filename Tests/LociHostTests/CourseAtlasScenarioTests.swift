import Foundation
import LociAgents
import LociModel
import LociStore
import Testing

@testable import LociHost

extension CourseScenarioTests {
  func atlas(pointingAt lesson: Lesson.ID) throws -> CourseAtlas {
    let json =
      #"{"gist": "Any two majorities intersect.", "blocks": [{"kind": "cards", "title": "Safety", "#
      + #""cards": [{"title": "Quorum", "points": ["Two majorities share a node"], "lessons": ["\#(lesson)"]}]}]}"#
    return try JSONDecoder().decode(CourseAtlas.self, from: Data(json.utf8))
  }

  @Test("Opening a lesson for the first time updates the atlas without starting the next lesson")
  func growsTheAtlas() async throws {
    try await withCourseHost { host, place, agent in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      let plan = course.lessons
      try place.store.writeLesson("First text.", in: course.id, lesson: plan[0].id)
      try place.store.writeCourseAtlas(atlas(pointingAt: plan[0].id), in: course.id)
      _ = try await host.run(OpenLesson(course: course.id, lesson: plan[0].id))
      #expect(
        try await host.coursePage(course.id).course.pendingEvents.map(\.event).contains(.drawAtlas(plan[0].id)))
      let session = try await turn(for: course.id, on: agent)
      let access = try await tag(for: course.id, on: agent)
      guard
        case .failed(.invalidRequest) = await answer(
          .writeLesson(plan[1].id, markdown: "Second text."), from: access, on: host)
      else {
        Issue.record("Opening the lesson started a writing turn")
        return
      }
      #expect(await session.prompts.last?.contains("The person opened lesson \(plan[0].id)") == true)
      let stray = await answer(.atlas(try atlas(pointingAt: #require(Lesson.ID("paxos")))), from: access, on: host)
      guard case .failed(.invalidRequest(let reason)) = stray else {
        Issue.record("An atlas pointing outside the plan was saved")
        return
      }
      #expect(reason.contains("not in the plan: paxos"))
      try await run(.atlas(atlas(pointingAt: plan[1].id)), in: access, on: host)
      await session.finish()
      try await idle(course.id, on: host)
      let page = try await host.coursePage(course.id)
      #expect(page.atlas == (try atlas(pointingAt: plan[1].id)))
      #expect(page.lessons[1].body == .unwritten)
      #expect(page.course.pendingEvents.isEmpty)
      _ = try await host.run(OpenLesson(course: course.id, lesson: plan[0].id))
      #expect(try await host.coursePage(course.id).course.pendingEvents.isEmpty)
    }
  }

  @Test("A course without an atlas does not ask for one when a lesson is opened")
  func noAtlasNoWork() async throws {
    try await withCourseHost { host, place, _ in
      let course = try seed(stage: .writing, in: place, id: EntityID())
      try place.store.writeLesson("First text.", in: course.id, lesson: course.lessons[0].id)
      try place.store.writeLesson("Second text.", in: course.id, lesson: course.lessons[1].id)
      _ = try await host.run(OpenLesson(course: course.id, lesson: course.lessons[0].id))
      #expect(try await host.coursePage(course.id).course.pendingEvents.isEmpty)
    }
  }
}
