import Foundation
import LociModel
import LociStore

extension AgentContext {
  /// Recently read, for the main conversation, means within this many milliseconds.
  static let recentReading: Int64 = 30 * 60 * 1000
  /// Today's and yesterday's notes are cut to their last this many characters.
  static let todaysNotes = 12_000
  static let yesterdaysNotes = 6_000

  /// What Loci is told before a message in `conversation`, the person having last said something there at
  /// `since`. The message counts toward how tired Loci is.
  func turnContext(for conversation: ConversationRef, since: Timestamp?) async -> TurnContext {
    let feeling = await feelings.heard(in: conversation)
    let now = environment.now()
    let timeZone = environment.timeZone
    let today = Day(containing: now, in: timeZone)
    let yesterday = today.adding(days: -1)
    let after = since ?? Timestamp(millisecondsSince1970: now.millisecondsSince1970 - 24 * 3_600_000)
    let events = (try? database.events(after: after)) ?? []
    let panels = store.panels().compactMap(\.panel)
    let marks = store.panelState().marks
    let summary =
      PanelSummary.applies(to: panels, marks: marks)
      ? [TurnContext.ShownFile(path: PanelSummary.heading, text: PanelSummary.of(panels, marks: marks), keep: nil)]
      : []
    var context = TurnContext(
      now: now, timeZone: timeZone, conversation: conversation,
      happenings: events.compactMap { happening($0, today: today) }, open: open(in: conversation, at: now),
      feeling: feeling,
      files: [
        .init(path: "MEMORY.md", text: (try? store.agentText(.memory)) ?? "", keep: nil),
        .init(path: "notes/\(today).md", text: (try? store.dayNotes(of: today)) ?? "", keep: Self.todaysNotes),
        .init(
          path: "notes/\(yesterday).md", text: (try? store.dayNotes(of: yesterday)) ?? "", keep: Self.yesterdaysNotes),
      ] + summary)
    if conversation == .main {
      let news = runNews(since: after)
      context.runs = news.runs
      context.followUps = news.followUps
      context.told = news.told
    }
    return context
  }

  /// One fact, without a word on how to feel about it; `nil` for an item that is gone.
  private func happening(_ logged: LoggedEvent, today: Day) -> String? {
    guard let item = try? store.item(logged.event.item) else { return nil }
    let day = Day(containing: logged.at, in: environment.timeZone)
    let time = TimeOfDay(of: logged.at, in: environment.timeZone)
    let when = day == today ? "\(time)" : "\(day) \(time)"
    let named = "\"\(item.title)\" (library/\(item.id))"
    switch logged.event {
    case .finishedReading:
      return "- \(when) finished reading \(named)"
    case .saved:
      return "- \(when) saved \(Self.kind(of: item)) \(named) to the library"
    case .highlighted(_, let id):
      let note = store.notes(on: .item(item.id)).value.first { $0.id == id }
      if let note, note.isWhole {
        return "- \(when) wrote about the whole of \(named)" + Self.quoted(note.thought)
      }
      return "- \(when) highlighted in \(named)"
        + Self.quoted(note?.excerpt ?? note?.pictures.first.map { "[picture: \($0)]" })
    }
  }

  private static func quoted(_ text: String?) -> String {
    text.map { ": \"\($0.replacing("\n", with: " "))\"" } ?? ""
  }

  private func open(in conversation: ConversationRef, at now: Timestamp) -> String? {
    switch conversation {
    case .item(let id):
      guard let item = try? store.item(id) else { return nil }
      return "\"\(item.title)\", \(Self.kind(of: item)) (library/\(id))"
    case .course(let course):
      guard let document = try? store.course(course) else { return nil }
      return "\"\(document.title)\" (courses/\(course))"
    case .main:
      guard let (content, at) = try? database.latestReading(), case .item(let id) = content,
        now.millisecondsSince1970 - at.millisecondsSince1970 <= Self.recentReading,
        let item = try? store.item(id)
      else { return nil }
      return "the person was just reading \"\(item.title)\", \(Self.kind(of: item)) (library/\(id))"
    }
  }

  static func kind(of item: Item) -> String {
    switch item.kind {
    case .article: "an article"
    case .paper: "a paper"
    case .video: "a video"
    case .audio: "an audio episode"
    case .repository: "a repository"
    }
  }
}

/// What a new session is told of the conversation so far, so it carries on where the last one stopped.
enum Recap {
  static let messages = 20
  static let characters = 8_000

  /// The person's words and Loci's replies since the conversation last started over, the latest first
  /// kept; `nil` when there are none.
  static func of(_ stored: [Message]) -> String? {
    let since = stored.lastIndex { $0.body == .startedOver }.map { stored.index(after: $0) } ?? stored.startIndex
    var lines: [String] = []
    var length = 0
    for message in stored[since...].reversed() {
      let line: String
      switch message.body {
      case .prompt(let prompt) where prompt.purpose == .chat: line = "Person: " + prompt.text
      case .reply(let text): line = "Companion: " + text
      default: continue
      }
      guard lines.count < messages, length + line.count <= characters else { break }
      lines.append(line)
      length += line.count
    }
    guard !lines.isEmpty else { return nil }
    return "Where we left off (your session was renewed; every word is in `conversations/`):\n\n"
      + lines.reversed().joined(separator: "\n\n") + "\n\n---\n\n"
  }
}
