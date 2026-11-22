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
    case .atlas(let path):
      let data: Data
      do {
        data = Data(try readText(file(at: path)).utf8)
      } catch {
        throw UsageError("Cannot read \(path) as UTF-8 JSON. Use loci course atlas <file.json>.")
      }
      do {
        return .atlas(try JSONDecoder().decode(CourseAtlas.self, from: data))
      } catch {
        throw UsageError("\(path) is not a valid atlas. \(Self.reason(error)) Run loci help for the format.")
      }
    case .writeLesson(let id, let path):
      let file = file(at: path)
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

  private func file(at path: String) -> URL {
    (path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: path)).standardizedFileURL
  }

  private static func reason(_ error: any Error) -> String {
    switch error {
    case DecodingError.dataCorrupted(let context): context.debugDescription
    case DecodingError.keyNotFound(let key, let context):
      "\((context.codingPath + [key]).map(\.stringValue).joined(separator: ".")) is missing."
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
      "\(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
    default: String(describing: error)
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
    case .atlas: return "Saved the atlas."
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
