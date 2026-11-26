import Foundation
import LociModel

/// `loci source …`: what the app fetches by itself for the home page's panels.
enum SourceRequest: Hashable, Sendable {
  /// Reads the script from standard input.
  case save(name: String, title: String, every: SourceEvery, window: SourceWindow?)
  /// Runs the saved samples again; `newScript` reads the script to try from standard input.
  case test(String, newScript: Bool)
  case show(String)
  case list

  static let usage =
    "loci source save <name> --title <title> --every <1m|15m|1h> [--between HH:mm-HH:mm] [--weekdays] < script.js"
    + " | loci source test <name> [--script < script.js] | loci source show <name> | loci source list"

  static func parse(_ words: [String]) throws(UsageError) -> SourceRequest {
    var words = words
    guard !words.isEmpty else { throw UsageError(usage) }
    let verb = words.removeFirst()
    switch verb {
    case "list" where words.isEmpty: return .list
    case "show" where words.count == 1: return .show(words[0])
    case "test":
      let newScript = words.contains("--script")
      words.removeAll { $0 == "--script" }
      guard words.count == 1 else { throw UsageError(usage) }
      return .test(words[0], newScript: newScript)
    case "save": return try save(words)
    default: throw UsageError(usage)
    }
  }

  private static func save(_ words: [String]) throws(UsageError) -> SourceRequest {
    var words = words
    let weekdays = words.contains("--weekdays")
    words.removeAll { $0 == "--weekdays" }
    let title = try take("--title", from: &words)
    let every = try take("--every", from: &words)
    let between = try take("--between", from: &words)
    guard words.count == 1, let name = words.first else { throw UsageError(usage) }
    if let problem = DataSourceCheck.problems(ofName: name).first { throw UsageError(problem.reason) }
    guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw UsageError("--title needs the source's title: --title \"ETF 溢价\"")
    }
    guard let every, let often = SourceEvery(every) else {
      throw UsageError("--every needs how often to fetch, in minutes or hours: --every 1m, 15m or 1h")
    }
    var window: SourceWindow?
    if let between {
      guard let read = SourceWindow(between, weekdays: weekdays) else {
        throw UsageError("--between needs a span of one day, such as 09:30-15:00")
      }
      window = read
    } else if weekdays {
      throw UsageError("--weekdays goes with --between: --between 09:30-15:00 --weekdays")
    }
    return .save(name: name, title: title, every: often, window: window)
  }

  private static func take(_ flag: String, from words: inout [String]) throws(UsageError) -> String? {
    guard let index = words.firstIndex(of: flag) else { return nil }
    guard words.indices.contains(index + 1) else { throw UsageError("\(flag) needs a value: \(usage)") }
    let value = words[index + 1]
    words.removeSubrange(index...(index + 1))
    return value
  }
}

extension Tool {
  func source(_ request: SourceRequest, json: Bool) async throws(Failure) -> Outcome {
    switch request {
    case .save(let name, let title, let every, let window):
      let script = String(decoding: readInput(), as: UTF8.self)
      let source = DataSource(name: name, title: title, every: every, window: window, script: script)
      let problems = DataSourceCheck.problems(in: source)
      guard problems.isEmpty else { return .failed(SourceWords.refused(problems)) }
      let reply = try await line.run(SaveDataSource(source))
      if json { return .worked(SourceWords.outside(json: reply, of: name)) }
      switch try Failure.decoding(SourceOutcome.self, from: reply) {
      case .records(let records): return .worked(SourceWords.saved(source, records))
      case .failed(let problems): return .failed(SourceWords.failedToFetch(problems.all, of: name))
      }
    case .test(let name, let newScript):
      let script = newScript ? String(decoding: readInput(), as: UTF8.self) : nil
      let reply = try await line.run(TestDataSource(name, script: script))
      if json { return .worked(SourceWords.outside(json: reply, of: name)) }
      let replays = try Failure.decoding([SourceReplay].self, from: reply)
      guard !replays.isEmpty else { return .failed("\(name) keeps no samples yet; save it to fetch one.") }
      let text = SourceWords.outside(
        replays.map { SourceWords.replay($0, timeZone: timeZone) }.joined(separator: "\n\n"), of: name, "test")
      let failed = replays.contains { if case .failed = $0.outcome { true } else { false } }
      return failed ? .failed(text) : .worked(text)
    case .show(let name):
      let reply = try await line.run(ListDataSources())
      let entries = try Failure.decoding([DataSourceEntry].self, from: reply)
      guard let entry = entries.first(where: { $0.source.name == name }) else {
        return .failed("There is no source \(name). Run `loci source list` to see them.")
      }
      if json { return .worked(SourceWords.outside(json: try Failure.encoding(entry), of: name)) }
      return .worked(SourceWords.entry(entry, timeZone: timeZone))
    case .list:
      let reply = try await line.run(ListDataSources())
      let entries = try Failure.decoding([DataSourceEntry].self, from: reply)
      if json {
        return .worked(
          Self.list(
            try entries.map { entry throws(Failure) in
              ExternalContent.json(try Failure.encoding(entry), from: "source \(entry.source.name)")
            }))
      }
      guard !entries.isEmpty else { return .worked("There are no sources yet.") }
      return .worked(entries.map { SourceWords.line($0, timeZone: timeZone) }.joined(separator: "\n"))
    }
  }
}

/// What `loci source` prints, for Loci to read. What a source got, and what its script said while it failed,
/// came from outside: it is marked as such, so the records' text never reads as instructions. Printed as JSON,
/// it is marked in the JSON, so the reply still reads as JSON.
enum SourceWords {
  static func outside(_ text: String, of source: String, _ step: String) -> String {
    ExternalContent.wrap(text, from: "source \(source)", tool: step)
  }

  static func outside(json: Data, of source: String) -> String {
    Tool.text(ExternalContent.json(json, from: "source \(source)"))
  }

  static func failedToFetch(_ problems: [SourceProblem], of source: String) -> String {
    "The source was not saved. What its fetch said:\n"
      + outside(problems.map { "- \($0)" }.joined(separator: "\n"), of: source, "fetch")
      + "\nFix the script and save it again."
  }

  static func refused(_ problems: [SourceProblem]) -> String {
    (["The source was not saved. Fix each of these and save it again:"] + problems.map { "- \($0)" })
      .joined(separator: "\n")
  }

  static func saved(_ source: DataSource, _ records: [String: SourceRecord]) -> String {
    let window = source.window.map { " between \($0)" } ?? ""
    return """
      Saved \(source.name). It is fetched every \(source.every)\(window). This fetch got:
      \(outside(SourceWords.records(records, source: source.name), of: source.name, "save"))
      Point panel rows at \(source.name).<record>.<field>.
      """
  }

  static func replay(_ replay: SourceReplay, timeZone: TimeZone) -> String {
    let at = time(replay.at, timeZone: timeZone)
    switch replay.outcome {
    case .records(let records): return "Sample from \(at):\n\(Self.records(records, source: nil))"
    case .failed(let problems):
      return "Sample from \(at) failed:\n" + problems.all.map { "- \($0)" }.joined(separator: "\n")
    }
  }

  static func line(_ entry: DataSourceEntry, timeZone: TimeZone) -> String {
    "\(entry.source.name)  \(entry.source.title), every \(entry.source.every)  \(state(entry, timeZone: timeZone))"
  }

  static func entry(_ entry: DataSourceEntry, timeZone: TimeZone) -> String {
    let source = entry.source
    var parts = [
      "\(source.name)  \(source.title)", "every \(source.every)\(source.window.map { " between \($0)" } ?? "")",
      state(entry, timeZone: timeZone), "\(entry.samples) sample(s) kept",
    ]
    if let snapshot = entry.snapshot {
      parts.append(outside(records(snapshot.records, source: source.name), of: source.name, "show"))
    }
    parts.append("Script:\n\(source.script)")
    return parts.joined(separator: "\n")
  }

  private static func state(_ entry: DataSourceEntry, timeZone: TimeZone) -> String {
    guard let snapshot = entry.snapshot else { return "never fetched" }
    let got = "got \(time(snapshot.fetched, timeZone: timeZone))"
    return snapshot.isStale ? "\(got), failed \(snapshot.failures) time(s) since" : got
  }

  /// Each record's fields, a list of points or candles by how many there are.
  static func records(_ records: [String: SourceRecord], source: String?) -> String {
    guard !records.isEmpty else { return "  (no records)" }
    return records.sorted { $0.key < $1.key }.map { key, fields in
      let values = fields.sorted { $0.key < $1.key }.map { name, value in "\(name)=\(Self.value(value))" }
      return "  \(source.map { "\($0)." } ?? "")\(key): \(values.joined(separator: ", "))"
    }.joined(separator: "\n")
  }

  private static func value(_ value: SourceValue) -> String {
    switch value {
    case .number(let number): number.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    case .text(let text): "\"\(text)\""
    case .points(let points): "\(points.count) points"
    case .candles(let candles): "\(candles.count) candles"
    }
  }

  private static func time(_ moment: Timestamp, timeZone: TimeZone) -> String {
    TimerWords.moment(moment, in: timeZone)
  }
}
