import Foundation
import LociHost
import LociModel

/// Plays one scenario against a host, through the same commands the app uses.
struct Runner {
  let host: LocalHost
  let root: URL
  let clock = ContinuousClock()

  func run(_ scenario: Scenario) async throws -> Evidence {
    let started = clock.now
    let mentor = try await host.run(CreateMentor(request: scenario.opening))
    let timeline = Timeline()
    let watching = Task {
      for await feed in host.subscribe(OneMentor(mentor: mentor.id)) {
        guard case .value(let page) = feed else { continue }
        await timeline.saw(page, after: seconds(since: started))
      }
    }
    defer { watching.cancel() }

    let firstEnded = await idle(mentor.id, within: .seconds(scenario.minutes * 60))
    if !firstEnded {
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }
    let before = try await host.conversation(of: mentor.id).messages.count
    _ = try await host.run(SendMessage(mentor: mentor.id, text: scenario.probe))
    if !(await idle(mentor.id, within: .seconds(600))) {
      _ = try await host.run(StopTurn(mentor: mentor.id))
    }

    let conversation = try await host.conversation(of: mentor.id).messages
    let probeAnswer = conversation.dropFirst(before).compactMap { message -> String? in
      if case .reply(let text) = message.body { text } else { nil }
    }.joined(separator: "\n")
    let page = try await host.run(ReadCatalog(mentor: mentor.id))
    let times = await timeline.times
    return Evidence(
      scenario: scenario, catalog: page.catalog, lessons: try await lessons(of: page), conversation: conversation,
      catalogAfter: times.catalog, firstLessonAfter: times.firstLesson, stoppedFirstTurn: !firstEnded,
      probeAnswer: probeAnswer)
  }

  /// Waits for the mentor to finish its turn. `false` when it is still working after `limit`.
  private func idle(_ mentor: EntityID, within limit: Duration) async -> Bool {
    let feed = host.subscribe(MentorConversation(mentor: mentor))
    return await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        try? await Task.sleep(for: .seconds(1))
        for await delivered in feed {
          if case .value(let conversation) = delivered, conversation.turn == nil { return true }
        }
        return false
      }
      group.addTask {
        try? await Task.sleep(for: limit)
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
  }

  private func lessons(of page: MentorPage) async throws -> [Evidence.WrittenLesson] {
    let titles = Dictionary(
      (page.catalog?.chapters ?? []).flatMap(\.lessons).map { ($0.slug, $0.title) }, uniquingKeysWith: { a, _ in a })
    var written: [Evidence.WrittenLesson] = []
    for slug in page.writtenLessons {
      let ref = LessonRef(mentor: page.mentor.id, lesson: slug)
      let body = try await host.run(ReadLessonText(lesson: ref))
      written.append(
        Evidence.WrittenLesson(
          slug: slug.description, title: titles[slug] ?? slug.description, sources: sources(of: ref), body: body))
    }
    return written
  }

  /// The entries under `sources:` in the lesson file's front matter, links included, which the host only
  /// turns into citations once they are fetched.
  private func sources(of lesson: LessonRef) -> [String] {
    let mentors = root.appending(path: "mentors")
    let folders = (try? FileManager.default.contentsOfDirectory(atPath: mentors.path(percentEncoded: false))) ?? []
    guard let folder = folders.first(where: { $0.hasSuffix(lesson.mentor.description) }),
      let text = try? String(
        contentsOf: mentors.appending(path: folder).appending(path: "lessons/\(lesson.lesson).md"), encoding: .utf8)
    else { return [] }
    return FrontMatter.sources(in: text)
  }

  private func seconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = clock.now - start
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
  }
}

/// When the catalog and the first lesson first appeared.
actor Timeline {
  private(set) var times: (catalog: Double?, firstLesson: Double?) = (nil, nil)

  func saw(_ page: MentorPage, after seconds: Double) {
    if times.catalog == nil, page.catalog?.chapters.isEmpty == false { times.catalog = seconds }
    if times.firstLesson == nil, !page.writtenLessons.isEmpty { times.firstLesson = seconds }
  }
}

enum FrontMatter {
  /// The list under `sources:` between the opening `---` lines.
  static func sources(in text: String) -> [String] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
      let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
    else { return [] }
    var inSources = false
    var found: [String] = []
    for line in lines[1..<end] {
      if line.hasPrefix("sources:") {
        inSources = true
      } else if inSources, line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
        let entry = line.trimmingCharacters(in: .whitespaces).dropFirst(2).trimmingCharacters(in: .whitespaces)
        found.append(entry.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")))
      } else if !line.hasPrefix(" ") {
        inSources = false
      }
    }
    return found
  }
}
