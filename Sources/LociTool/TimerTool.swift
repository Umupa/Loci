import Foundation
import LociModel

/// `loci schedule …`: timers that come due again and again.
enum ScheduleRequest: Hashable, Sendable {
  /// Reads the schedule's JSON from standard input.
  case add(String)
  case list
  case remove(String)

  static let usage = "loci schedule add <name> < schedule.json | loci schedule list | loci schedule remove <name>"

  static func parse(_ words: [String]) throws(UsageError) -> ScheduleRequest {
    switch (words.first, words.count) {
    case ("list", 1): return .list
    case ("add", 2):
      if let problem = PanelCheck.problems(ofName: words[1]).first { throw UsageError(problem.reason) }
      return .add(words[1])
    case ("remove", 2): return .remove(words[1])
    default: throw UsageError(usage)
    }
  }
}

/// `loci followup …`: a timer the companion sets for itself, to come due once.
enum FollowUpRequest: Hashable, Sendable {
  case add(FollowUpTime, String)
  case list
  case cancel(EntityID)

  static let usage =
    "loci followup <YYYY-MM-DD [HH:mm] | HH:mm | in <n>m|h|d> <what> | loci followup list | loci followup cancel <id>"

  static func parse(_ words: [String]) throws(UsageError) -> FollowUpRequest {
    switch (words.first, words.count) {
    case ("list", 1): return .list
    case ("cancel", 2):
      guard let id = EntityID(words[1]) else { throw UsageError("loci followup cancel takes an id, as list prints it") }
      return .cancel(id)
    default: break
    }
    var rest = ArraySlice(words)
    let time: FollowUpTime
    if rest.first == "in", rest.count > 1, let minutes = minutes(rest[rest.startIndex + 1]) {
      time = .after(minutes: minutes)
      rest = rest.dropFirst(2)
    } else if let first = rest.first, let day = Day(first) {
      rest = rest.dropFirst()
      let clock = rest.first.flatMap(TimeOfDay.init)
      if clock != nil { rest = rest.dropFirst() }
      time = .at(day, clock)
    } else if let first = rest.first, let clock = TimeOfDay(first) {
      time = .next(clock)
      rest = rest.dropFirst()
    } else {
      throw UsageError(usage)
    }
    let what = rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !what.isEmpty else { throw UsageError("Say what to follow up on: \(usage)") }
    return .add(time, what)
  }

  /// `90m`, `3h`, `2d`.
  private static func minutes(_ word: String) -> Int? {
    guard let match = word.wholeMatch(of: /(\d+)([mhd])/), let count = Int(match.1), count > 0 else { return nil }
    switch match.2 {
    case "m": return count
    case "h": return count * 60
    default: return count * 24 * 60
    }
  }
}

extension Tool {
  func schedule(_ request: ScheduleRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .add(let name):
      let draft: ScheduleDraft
      do {
        draft = try JSONDecoder().decode(ScheduleDraft.self, from: readInput())
      } catch {
        return .failed(TimerWords.unreadable(error))
      }
      let reply = try await line.run(AddSchedule(name, draft))
      if json { return .worked(Self.text(reply)) }
      return .worked(TimerWords.added(try Failure.decoding(ScheduleEntry.self, from: reply), in: timeZone))
    case .list:
      let reply = try await line.run(ListTimers())
      if json { return .worked(Self.text(reply)) }
      let timers = try Failure.decoding(Timers.self, from: reply)
      guard !timers.schedules.isEmpty else { return .worked("There are no schedules yet.") }
      return .worked(timers.schedules.map { TimerWords.line($0, in: timeZone) }.joined(separator: "\n"))
    case .remove(let name):
      let timers = try Failure.decoding(Timers.self, from: try await line.run(ListTimers()))
      let entries = timers.schedules.filter { $0.name == name }
      guard let entry = entries.first(where: { if case .schedule = $0.ref { true } else { false } }) ?? entries.first
      else { return .failed("There is no schedule \(name). Run `loci schedule list` to see them.") }
      let reply = try await line.run(RemoveSchedule(entry.ref))
      if json { return .worked(Self.text(reply)) }
      if case .panel = entry.ref { return .worked("The panel \(name) is no longer refreshed; it stays as it is.") }
      return .worked("Removed \(name).")
    }
  }

  func followUp(_ request: FollowUpRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .add(let time, let what):
      let reply = try await line.run(AddFollowUp(time, what))
      if json { return .worked(Self.text(reply)) }
      let followUp = try Failure.decoding(FollowUp.self, from: reply)
      return .worked("Set for \(TimerWords.moment(followUp.due, in: timeZone)): \(followUp.what)  (\(followUp.id))")
    case .list:
      let reply = try await line.run(ListTimers())
      if json { return .worked(Self.text(reply)) }
      let followUps = try Failure.decoding(Timers.self, from: reply).followUps
      guard !followUps.isEmpty else { return .worked("There are no follow-ups.") }
      return .worked(
        followUps.map { "\($0.id)  \(TimerWords.moment($0.due, in: timeZone))  \($0.what)" }.joined(separator: "\n"))
    case .cancel(let id):
      let reply = try await line.run(CancelFollowUp(id))
      return .worked(json ? Self.text(reply) : "Cancelled.")
    }
  }
}

/// What `loci schedule` and `loci followup` print, for Loci to read.
enum TimerWords {
  static func added(_ entry: ScheduleEntry, in timeZone: TimeZone) -> String {
    "Added \(entry.name), \(PanelWords.every(entry.every.refresh)), \(place(entry.destination))."
      + (entry.next.map { " It first runs \(moment($0, in: timeZone))." } ?? "")
  }

  static func line(_ entry: ScheduleEntry, in timeZone: TimeZone) -> String {
    let kind = if case .panel = entry.ref { " (the panel's refresh)" } else { "" }
    let when = entry.paused ? "paused" : entry.next.map { "next \(moment($0, in: timeZone))" } ?? ""
    return
      "\(entry.name)\(kind)  \(entry.title), \(PanelWords.every(entry.every.refresh)), \(place(entry.destination));"
      + " \(when)"
  }

  static func place(_ destination: Destination) -> String {
    switch destination {
    case .panel(let name): "into the panel \(name)"
    case .notes: "into your notes only"
    }
  }

  static func moment(_ moment: Timestamp, in timeZone: TimeZone) -> String {
    "\(Day(containing: moment, in: timeZone)) \(TimeOfDay(of: moment, in: timeZone))"
  }

  static func unreadable(_ error: any Error) -> String {
    "The schedule was not added: standard input must be JSON like "
      + #"{"title": "…", "follow": "…", "every": {"every": "day", "at": "21:00"}, "panel": "…"}"#
      + ". \(error.localizedDescription)"
  }
}
