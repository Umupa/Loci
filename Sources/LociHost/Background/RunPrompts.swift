import Foundation
import LociModel
import LociStore

/// What a run in the background is asked: for each event, what it is for and what the last run of the same
/// schedule found, and the panel it keeps as it is now. Nothing of any conversation.
struct RunPrompts {
  let context: AgentContext

  private var store: Store { context.store }
  private var timeZone: TimeZone { context.environment.timeZone }

  /// `brief` is what the app worked out for a daily review.
  func text(for run: Run, redo: Bool, brief: ReviewBrief? = nil) throws(HostError) -> String {
    let today = Day(containing: context.environment.now(), in: timeZone)
    let parts = try run.kind.sources.map { source throws(HostError) in
      try text(for: source, run: run, today: today, brief: brief)
    }
    var text =
      parts.count == 1
      ? parts[0]
      : "Several things came due together. Do each in turn, in this one session.\n\n"
        + parts.joined(separator: "\n\n---\n\n")
        + "\n\nWhen all are done, end with one sentence that sums up everything you found."
    if redo {
      text +=
        "\n\nAn earlier try of this run stopped partway. Lines tagged [run/\(run.id)] in today's notes are from it:"
        + " do not add them again. Save panels whole, as always."
    }
    return text
  }

  private func text(for source: Event.Source, run: Run, today: Day, brief: ReviewBrief?) throws(HostError) -> String {
    switch source {
    case .panel(let name, _):
      guard let panel = store.panel(named: name)?.panel else { throw .notFound(name) }
      return try context.prompts.panel(panel, hidden: store.panelState().marks[name] ?? [:])
    case .schedule(let id):
      guard let schedule = try attempt({ try context.database.schedule(id) }) else { throw .notFound(id.description) }
      return try text(for: schedule, run: run, today: today)
    case .followUp(let id):
      guard let followUp = try attempt({ try context.database.followUp(id) }) else { throw .notFound(id.description) }
      return text(for: followUp, run: run, today: today)
    case .review(let day):
      let previous = (try? context.database.latestReview(before: day)).flatMap { previous in
        previous.day == day.adding(days: -1)
          ? (day: previous.day, at: TimeOfDay(of: previous.startedAt, in: timeZone)) : nil
      }
      return context.prompts.review(of: day, since: previous, brief: brief)
    }
  }

  private func text(for schedule: Schedule, run: Run, today: Day) throws(HostError) -> String {
    var destination = "It goes only into your notes; there is no panel for it."
    var panelText = ""
    var hiddenNote = ""
    if case .panel(let name) = schedule.destination, let panel = store.panel(named: name)?.panel {
      destination =
        "Keep the panel `\(name)` current with what you find: rewrite it whole with `\"$LOCI\" panel save \(name)`,"
        + " the JSON on standard input, keeping its title, sources and follow; the first row is one sentence that"
        + " sums it up. Items with `\"by\": \"you\"` are the person's; the app keeps them whatever you save."
      let hidden = Prompts.hidden(in: panel, marks: store.panelState().marks[name] ?? [:])
      if !hidden.isEmpty { hiddenNote = ", or what the person no longer wants to see in the panel" }
      panelText = hidden + "\nThe panel now:\n\n```json\n\(try Prompts.json(panel))\n```\n"
    }
    let last = try attempt { try context.database.runs(of: schedule.ref, limit: 5) }
      .first { $0.id != run.id && $0.isFinished }
    let previous =
      last.flatMap { (try? store.runRecord(at: $0.record)).flatMap(\.self) }
      .map { "What the last run of this schedule found (`\(last?.record ?? "")`):\n\n\($0)\n" }
      ?? "This is the schedule's first run.\n"
    return context.prompts.schedule
      .replacing("{{name}}", with: schedule.name)
      .replacing("{{title}}", with: schedule.title)
      .replacing("{{follow}}", with: schedule.follow)
      .replacing("{{where}}", with: destination)
      .replacing("{{hiddenNote}}", with: hiddenNote)
      .replacing("{{today}}", with: today.description)
      .replacing("{{run}}", with: run.id.description)
      .replacing("{{previous}}", with: previous)
      .replacing("{{panel}}", with: panelText)
  }

  private func text(for followUp: FollowUp, run: Run, today: Day) -> String {
    let set = "\(Day(containing: followUp.createdAt, in: timeZone))"
    let due = "\(Day(containing: followUp.due, in: timeZone)) \(TimeOfDay(of: followUp.due, in: timeZone))"
    let place = followUp.conversation.map { " in the conversation \(TurnContext.name(of: $0))" } ?? ""
    return context.prompts.followUp
      .replacing("{{set}}", with: set)
      .replacing("{{due}}", with: due)
      .replacing("{{where}}", with: place)
      .replacing("{{what}}", with: followUp.what)
      .replacing("{{today}}", with: today.description)
      .replacing("{{run}}", with: run.id.description)
  }
}

extension Run {
  var isFinished: Bool {
    if case .finished = outcome { true } else { false }
  }

  var summary: String? {
    if case .finished(let summary, _) = outcome { summary } else { nil }
  }
}
