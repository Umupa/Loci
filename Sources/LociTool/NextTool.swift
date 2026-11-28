import Foundation
import LociModel

/// `loci next …`: cards on the person's deck and approval cards.
enum NextRequest: Hashable, Sendable {
  case add(what: String, question: String, key: String?, deadline: Timestamp? = nil)
  case propose(Proposal, deadline: Timestamp? = nil)

  /// An approval as written, before its times are read in the person's time zone.
  enum Proposal: Hashable, Sendable {
    case event(title: String, at: Day, TimeOfDay?, until: TimeOfDay?, calendar: String?, why: String?)
    case reminder(title: String, at: Day?, TimeOfDay?, list: String?, why: String?)
  }

  static let usage =
    "loci next add <what> --ask <question> [--key <key>] [--deadline <ISO-8601>] | loci next propose "
    + "event <title> --at YYYY-MM-DD [HH:mm] [--until HH:mm] [--calendar <name>] [--why <line>] | loci next propose "
    + "reminder <title> [--at YYYY-MM-DD [HH:mm]] [--list <name>] [--why <line>]; both accept --deadline"

  static let onlyTwo =
    "loci next propose takes event or reminder. Paying, ordering, signing up and sending messages are not "
    + "something you can do for the person: say so."

  static func parse(_ words: [String]) throws(UsageError) -> NextRequest {
    guard let verb = words.first else { throw UsageError(usage) }
    let (plain, supplied) = try split(Array(words.dropFirst()))
    var options = supplied
    let deadline: Timestamp?
    if let text = options.removeValue(forKey: "deadline") {
      guard let parsed = Timestamp.parseISO8601(text) else {
        throw UsageError("--deadline needs ISO-8601 with an offset")
      }
      deadline = parsed
    } else {
      deadline = nil
    }
    switch verb {
    case "add":
      guard !plain.isEmpty, let question = options["ask"], options.keys.allSatisfy(["ask", "key"].contains) else {
        throw UsageError(usage)
      }
      return .add(what: plain.joined(separator: " "), question: question, key: options["key"], deadline: deadline)
    case "propose": return .propose(try proposal(plain, options), deadline: deadline)
    default: throw UsageError(usage)
    }
  }

  private static func proposal(_ plain: [String], _ options: [String: String]) throws(UsageError) -> Proposal {
    guard let kind = plain.first else { throw UsageError(usage) }
    let title = plain.dropFirst().joined(separator: " ")
    let at = options["at"].map { $0.split(separator: " ").map(String.init) }
    let day = at?.first.flatMap(Day.init)
    let time = at.flatMap { $0.count > 1 ? TimeOfDay($0[1]) : nil }
    guard at == nil || (day != nil && (at?.count == 1 || time != nil)) else {
      throw UsageError("--at is YYYY-MM-DD [HH:mm]")
    }
    switch kind {
    case "event":
      let until = options["until"].map(TimeOfDay.init)
      guard !title.isEmpty, let day, until != .some(nil),
        options.keys.allSatisfy(["at", "until", "calendar", "why"].contains)
      else { throw UsageError(usage) }
      return .event(
        title: title, at: day, time, until: until.flatMap(\.self), calendar: options["calendar"], why: options["why"])
    case "reminder":
      guard !title.isEmpty, options.keys.allSatisfy(["at", "list", "why"].contains) else { throw UsageError(usage) }
      return .reminder(title: title, at: day, time, list: options["list"], why: options["why"])
    default:
      throw UsageError(onlyTwo)
    }
  }

  /// The words before the first `--option`, and each option's words joined.
  private static func split(_ words: [String]) throws(UsageError) -> ([String], [String: String]) {
    var plain: [String] = []
    var options: [String: [String]] = [:]
    var current: String?
    for word in words {
      if word.hasPrefix("--"), word.count > 2 {
        let name = String(word.dropFirst(2))
        guard options[name] == nil else { throw UsageError("--\(name) is given twice") }
        options[name] = []
        current = name
      } else if let name = current {
        options[name, default: []].append(word)
      } else {
        plain.append(word)
      }
    }
    var joined: [String: String] = [:]
    for (name, words) in options {
      let value = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
      guard !value.isEmpty else { throw UsageError("--\(name) needs a value") }
      joined[name] = value
    }
    return (plain, joined)
  }
}

extension NextRequest.Proposal {
  /// The approval, its times read in `timeZone`. An event with no time is all day.
  func approval(in timeZone: TimeZone) -> (Approval, why: String?) {
    func moment(_ day: Day, _ time: TimeOfDay?) -> Timestamp {
      let minutes = Int64(time.map { $0.hour * 60 + $0.minute } ?? 0)
      return Timestamp(millisecondsSince1970: day.start(in: timeZone).millisecondsSince1970 + minutes * 60_000)
    }
    switch self {
    case .event(let title, let day, let time, let until, let calendar, let why):
      let start = moment(day, time)
      let end = time == nil ? moment(day.adding(days: 1), nil) : until.map { moment(day, $0) }
      return (.event(EventDraft(title: title, start: start, end: end, allDay: time == nil, calendar: calendar)), why)
    case .reminder(let title, let day, let time, let list, let why):
      return (
        .reminder(
          ReminderDraft(title: title, due: day.map { moment($0, time ?? TimeOfDay(hour: 9, minute: 0)) }, list: list)),
        why
      )
    }
  }
}

extension Tool {
  func next(_ request: NextRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .add(let what, let question, let key, let deadline):
      let reply = try await line.run(AddNextUp(what, asking: question, key: key, deadline: deadline))
      if json { return .worked(Self.text(reply)) }
      let card = try Failure.decoding(NextUp.self, from: reply)
      return .worked("On the deck: \(card.what)")
    case .propose(let proposal, let deadline):
      let (approval, why) = proposal.approval(in: timeZone)
      let reply = try await line.run(ProposeApproval(approval, why: why, deadline: deadline))
      if json { return .worked(Self.text(reply)) }
      return .worked("Waiting for the person to approve: \(approval.title)")
    }
  }
}
