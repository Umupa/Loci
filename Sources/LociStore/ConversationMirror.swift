import Foundation
import LociModel

/// `agent/conversations/<day>/<owner>-<session>.md`: what was said, as plain text Loci can search to find
/// what someone really said. Only the app writes these, a turn at a time.
extension Store {
  static let conversationsFolder = "conversations"

  /// Adds a turn to its session's copies, each message under the day it was said on in `timeZone`.
  public func mirror(_ messages: [Message], of session: SessionRecord, in timeZone: TimeZone) throws {
    for (day, text) in ConversationMirror.render(messages, in: timeZone) {
      let url = agentFolder.appending(path: Self.conversationsFolder).appending(path: day.description)
        .appending(path: "\(session.owner.key)-\(session.id).md")
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      let added = exists ? text : "# \(session.owner.key) · \(day)\n" + text
      let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_APPEND | O_CREAT, 0o644)
      guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      try handle.write(contentsOf: Data(added.utf8))
      try handle.close()
    }
  }
}

enum ConversationMirror {
  /// The messages as Markdown, by day. Thinking and the app's bookkeeping are left out; tools are one line
  /// each.
  static func render(_ messages: [Message], in timeZone: TimeZone) -> [(Day, String)] {
    var days: [(Day, String)] = []
    var speaker: String?
    for message in messages {
      guard let (who, text) = line(for: message.body) else { continue }
      let day = Day(containing: message.at, in: timeZone)
      if days.last?.0 != day {
        days.append((day, ""))
        speaker = nil
      }
      var block = ""
      if who != speaker {
        block += "\n### \(TimeOfDay(of: message.at, in: timeZone)) · \(who)\n\n"
        speaker = who
      }
      block += text + "\n"
      days[days.count - 1].1 += block
    }
    return days
  }

  private static func line(for body: Message.Body) -> (String, String)? {
    switch body {
    case .prompt(let prompt):
      let quoted = prompt.passage.map { "> " + $0.excerpt.replacing("\n", with: "\n> ") + "\n\n" } ?? ""
      switch prompt.purpose {
      case .chat: return ("You", quoted + prompt.text)
      case .course(.started), .course(.answered), .course(.confirmedGoal), .course(.askedToReviseGoal):
        return ("You", prompt.text)
      case .review, .panel, .run, .course: return ("App", prompt.text)
      }
    case .reply(let text):
      return ("Companion", text)
    case .tool(let tool):
      return ("Companion", "- \(tool.kind.rawValue): \(tool.subject ?? tool.name)")
    case .ended(.interrupted):
      return ("Companion", "_(stopped)_")
    case .ended(.failed(let reason)):
      return ("Companion", "_(failed: \(reason))_")
    case .ended(.unstarted(let provider, .notInstalled)):
      return ("Companion", "_(\(provider.rawValue) is not installed)_")
    case .ended(.unstarted(let provider, .wouldNotStart)):
      return ("Companion", "_(\(provider.rawValue) would not start)_")
    case .startedOver:
      return ("You", "/new")
    case .savedItem(let item):
      return ("Companion", "- saved to the library: library/\(item)")
    case .thinking, .savedToNote, .notice:
      return nil
    }
  }
}

extension Store {
  public func discardCourseConversation(_ course: EntityID) throws {
    let folder = agentFolder.appending(path: Self.conversationsFolder)
    let prefix = SessionOwner.conversation(.course(course)).key + "-"
    for day in subfolders(of: folder) {
      for file in files(in: day, withExtension: "md") where file.lastPathComponent.hasPrefix(prefix) {
        try discard(file)
      }
    }
  }
}
