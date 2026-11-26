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
    let home = conversation.home
    let files = store.home(home)
    let panels = files.panels().compactMap(\.panel)
    let marks = files.panelState().marks
    let summary =
      PanelSummary.applies(to: panels, marks: marks)
      ? [TurnContext.ShownFile(path: PanelSummary.heading, text: PanelSummary.of(panels, marks: marks), keep: nil)]
      : []
    let indexes: [TurnContext.ShownFile] =
      home == .chat
      ? [.init(path: "MEMORY.md", text: Self.index((try? store.agentText(.memory)) ?? ""), keep: nil)]
      : [
        .init(path: "../../MEMORY.md", text: Self.index((try? store.agentText(.memory)) ?? ""), keep: nil),
        .init(path: "MEMORY.md", text: Self.index(files.index()), keep: nil),
      ]
    var context = TurnContext(
      now: now, timeZone: timeZone, conversation: conversation,
      happenings: events.compactMap { happening($0, today: today) }, open: open(in: conversation, at: now),
      feeling: feeling,
      files: indexes + [
        .init(path: "notes/\(today).md", text: (try? files.dayNotes(of: today)) ?? "", keep: Self.todaysNotes),
        .init(
          path: "notes/\(yesterday).md", text: (try? files.dayNotes(of: yesterday)) ?? "", keep: Self.yesterdaysNotes),
      ] + summary)
    if conversation == .main {
      if let reconnect = connectorsToReconnect() { context.files.append(reconnect) }
      if let projects = projectLines() { context.files.append(projects) }
    }
    if conversation == home.conversation {
      let news = runNews(since: after, in: home)
      context.runs = news.runs
      context.followUps = news.followUps
      context.told = news.told
    }
    return context
  }

  /// One line for each project the chat may know of: its name and what it is doing.
  private func projectLines() -> TurnContext.ShownFile? {
    let lines = rememberedProjects().compactMap { project in
      project.name.map { "- \($0) (projects/\(project.id))" + (project.summary.isEmpty ? "" : ": \(project.summary)") }
    }
    guard !lines.isEmpty else { return nil }
    return TurnContext.ShownFile(
      path: "Projects (each has its own conversation and memory; you know only this line of each here)",
      text: lines.joined(separator: "\n"), keep: nil)
  }

  /// The connectors whose sign-in ran out, shown once and again when that changes.
  private func connectorsToReconnect() -> TurnContext.ShownFile? {
    let waiting = ((try? database.connectorRecords()) ?? []).compactMap { record -> String? in
      guard case .needsReconnecting(let why) = record.status else { return nil }
      return "- \(record.name) (\(record.id)): \(why)"
    }
    guard !waiting.isEmpty else { return nil }
    return TurnContext.ShownFile(
      path:
        "Connectors that need the person to reconnect them (mention it once; link [reconnect](loci://connectors/<id>))",
      text: waiting.joined(separator: "\n"), keep: nil)
  }

  /// The most lines of `MEMORY.md` a turn is given.
  static let indexLines = 200

  /// The index as a turn sees it: its first lines, and a word on how many more there are.
  static func index(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > indexLines else { return text }
    return lines.prefix(indexLines).joined(separator: "\n")
      + "\n(MEMORY.md has \(lines.count) lines; only the first \(indexLines) are here. In the daily review, sink "
      + "detail into memory/ so the index stays short.)"
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
    case .project:
      return nil
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
    case .book: "a book"
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
      case .reply(let text), .told(let text): line = "Companion: " + text
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
