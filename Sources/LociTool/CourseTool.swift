import Foundation
import LociModel

extension Tool {
  func course(_ command: CourseRequest, json: Bool) async -> Outcome {
    let request: CourseToolRequest
    do {
      request = try courseRequest(command)
    } catch {
      return Outcome(text: error.message, status: 2)
    }

    do throws(Failure) {
      let response = try await line.send(.course(request))
      return .worked(json ? Self.text(response) : try courseReply(response, for: request))
    } catch .host(.invalidRequest(let reason)) where reason != CourseToolRequest.scopeMessage {
      return Outcome(text: reason, status: 2)
    } catch {
      return .failed(error.message)
    }
  }

  private func courseRequest(_ command: CourseRequest) throws(UsageError) -> CourseToolRequest {
    switch command {
    case .ask: return .ask(try input(CourseQuestion.Draft.self, for: "loci course ask"))
    case .goal: return .goal(try input(CourseGoal.self, for: "loci course goal"))
    case .ready: return .ready
    case .addSource(let draft): return .addSource(draft)
    case .readSource(let id): return .readSource(id)
    case .listSources: return .listSources
    case .plan: return .plan(try input([Lesson].self, for: "loci course plan"))
    case .writeLesson(let id, let path):
      let file = (path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)).standardizedFileURL
      let markdown: String
      do {
        markdown = try readText(file)
      } catch {
        throw UsageError("Cannot read \(path) as UTF-8 Markdown. Use loci lesson write <lesson-id> <file.md>.")
      }
      guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw UsageError("Write some Markdown in \(path) before saving the lesson.")
      }
      return .writeLesson(id, markdown: markdown)
    }
  }

  private func input<Value: Decodable>(_ type: Value.Type, for command: String) throws(UsageError) -> Value {
    do {
      return try JSONDecoder().decode(type, from: readInput())
    } catch {
      throw UsageError("\(command) needs valid JSON on standard input. \(error). Run loci help for the format.")
    }
  }

  private func courseReply(_ response: Data, for request: CourseToolRequest) throws(Failure) -> String {
    switch request {
    case .ask: return "Asked the course question."
    case .goal: return "Updated the course goal."
    case .ready: return "The goal is ready. The person can start gathering sources."
    case .readSource: return "Marked the source read."
    case .plan: return "Saved the lesson plan."
    case .writeLesson(let lesson, _): return "Saved lesson \(lesson)."
    case .addSource:
      return Self.sourceLine(try Failure.decoding(CourseSource.self, from: response))
    case .listSources:
      let sources = try Failure.decoding([CourseSource].self, from: response)
      if sources.isEmpty { return "This course has no sources." }
      return sources.map(Self.sourceLine).joined(separator: "\n")
    }
  }

  private static func sourceLine(_ source: CourseSource) -> String {
    let pin = source.commit.map { " @ \($0)" } ?? ""
    return "\(source.id)  \(source.title)  \(source.kind.rawValue) · \(source.site)  "
      + "\(source.url.absoluteString)\(pin)  \(source.isRead ? "read" : "unread")"
  }
}
