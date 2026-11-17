import Foundation
import LociModel
import Testing

@testable import LociHost
@testable import LociStore

struct MentorScenarioTests {
  /// α1-S2: one sentence makes a mentor with an empty catalog, and the mentor list shows it.
  @Test func aSentenceMakesAMentorWithAnEmptyCatalog() async throws {
    try await withHost { host, _, _ in
      let mentors = host.subscribe(AllMentors())
      let mentor = try await host.run(CreateMentor(request: "  我想搞懂 Kubernetes 的调度器到底是怎么把 Pod 放到节点上的  "))

      #expect(mentor.name == "我想搞懂 Kubernetes 的调度器到底是怎")
      #expect(mentor.request == "我想搞懂 Kubernetes 的调度器到底是怎么把 Pod 放到节点上的")
      #expect(mentor.avatar == Mentor.portraits[0])
      #expect(mentor.color == MentorColor.palette[0])
      #expect(mentor.provider == .pi)
      #expect(mentor.permission == .full)
      let listed = await value(mentors) { $0 == [mentor] }
      #expect(listed != nil)
      let page = try await host.run(ReadCatalog(mentor: mentor.id))
      #expect(page.catalog?.chapters.isEmpty == true)
      #expect(page.writtenLessons.isEmpty)
    }
  }

  @Test(arguments: [
    ("Scheduling", "Scheduling"),
    ("Understand the Kubernetes scheduler", "Understand the"),
    ("Distributed systems and consensus", "Distributed systems and"),
  ])
  func aLongSentenceIsShortenedWithoutSplittingAWord(sentence: String, name: String) {
    #expect(MentorLook.name(from: sentence) == name)
  }

  @Test func eachNewMentorLooksDifferent() async throws {
    try await withHost { host, _, _ in
      let first = try await host.run(CreateMentor(request: "Scheduling"))
      let second = try await host.run(CreateMentor(request: "Storage engines"))

      #expect(second.avatar == Mentor.portraits[1])
      #expect(second.color == MentorColor.palette[1])
      #expect(first.avatar != second.avatar)
    }
  }

  @Test func anEmptySentenceIsRefused() async throws {
    try await withHost { host, _, _ in
      await #expect(throws: HostError.self) { try await host.run(CreateMentor(request: " \n ")) }
    }
  }

  @Test func renamingAndDeletingReachTheSubscriptions() async throws {
    try await withHost { host, _, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let page = host.subscribe(OneMentor(mentor: mentor.id))
      let shown = await value(page) { $0.mentor.name == "Scheduling" }
      #expect(shown != nil)

      _ = try await host.run(RenameMentor(mentor: mentor.id, name: "调度"))
      let renamed = await value(page) { $0.mentor.name == "调度" }
      #expect(renamed != nil)
      #expect(try await host.run(ListMentors()).map(\.name) == ["调度"])

      _ = try await host.run(DeleteMentor(mentor: mentor.id, notes: .delete))
      let gone = await first(page) { if case .unavailable = $0 { true } else { false } }
      #expect(gone == .unavailable(.notFound(mentor.id.description)))
      #expect(try await host.run(ListMentors()).isEmpty)
    }
  }

  /// α1-S5: a name changed in the Finder reaches both the list and the mentor's page.
  @Test func anOutsideEditReachesTheSubscriptions() async throws {
    try await withHost { host, place, _ in
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))
      let mentors = host.subscribe(AllMentors())
      let page = host.subscribe(OneMentor(mentor: mentor.id))
      let listed = await value(mentors) { $0.map(\.name) == ["Scheduling"] }
      #expect(listed != nil)

      let file = try place.store.mentorFolder(mentor.id).appending(path: "mentor.json")
      try place.edit(file) { $0.replacing("\"Scheduling\"", with: "\"排程\"") }

      let renamedList = await value(mentors) { $0.map(\.name) == ["排程"] }
      #expect(renamedList != nil)
      let renamedPage = await value(page) { $0.mentor.name == "排程" }
      #expect(renamedPage != nil)
    }
  }

  @Test func anUnchangedValueIsNotSentAgain() async throws {
    try await withHost { host, _, _ in
      let mentors = host.subscribe(AllMentors())
      let initial = await value(mentors) { $0.isEmpty }
      #expect(initial != nil)

      await host.follow([.mentor(EntityID()), .everything])
      let mentor = try await host.run(CreateMentor(request: "Scheduling"))

      var next = mentors.makeAsyncIterator()
      #expect(await next.next() == .value([mentor]))
    }
  }
}
