import Foundation

/// One value of a record, as `parse` gives it: a number, some text, a line of points `[[ms, value], ...]`,
/// or candles `[[ms, open, high, low, close], ...]`.
public enum SourceValue: Hashable, Sendable {
  case number(Double)
  case text(String)
  case points([SourcePoint])
  case candles([SourceCandle])

  /// `nil` for JSON that is none of the four, or an array that mixes points and candles.
  public init?(json: JSONValue) {
    switch json {
    case .integer, .number:
      guard let number = json.number, number.isFinite else { return nil }
      self = .number(number)
    case .string(let text): self = .text(text)
    case .array(let rows):
      let numbers = rows.map { row in row.array.map { cells in cells.map(\.number) } }
      guard numbers.allSatisfy({ $0?.allSatisfy({ $0?.isFinite == true }) == true }) else { return nil }
      let rows = numbers.map { $0?.compactMap { $0 } ?? [] }
      guard rows.allSatisfy({ ($0.first.map(abs) ?? 0) < Self.latestMoment }) else { return nil }
      if rows.allSatisfy({ $0.count == 2 }) {
        self = .points(rows.map { SourcePoint(at: Timestamp(millisecondsSince1970: Int64($0[0])), value: $0[1]) })
      } else if rows.allSatisfy({ $0.count == 5 }) {
        self = .candles(
          rows.map {
            SourceCandle(
              at: Timestamp(millisecondsSince1970: Int64($0[0])), open: $0[1], high: $0[2], low: $0[3], close: $0[4])
          })
      } else {
        return nil
      }
    default: return nil
    }
  }

  /// Milliseconds past which a point's time is not a moment but a mistake.
  private static let latestMoment = 1e15

  public var json: JSONValue {
    switch self {
    case .number(let number): .number(number)
    case .text(let text): .string(text)
    case .points(let points):
      .array(points.map { .array([.integer($0.at.millisecondsSince1970), .number($0.value)]) })
    case .candles(let candles):
      .array(
        candles.map {
          .array([
            .integer($0.at.millisecondsSince1970), .number($0.open), .number($0.high), .number($0.low),
            .number($0.close),
          ])
        })
    }
  }

  public var number: Double? {
    if case .number(let number) = self { number } else { nil }
  }
}

extension SourceValue: Codable {
  public init(from decoder: any Decoder) throws {
    let json = try JSONValue(from: decoder)
    guard let value = SourceValue(json: json) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not a source value: \(json.text)"))
    }
    self = value
  }

  public func encode(to encoder: any Encoder) throws {
    try json.encode(to: encoder)
  }
}

public struct SourcePoint: Hashable, Codable, Sendable {
  public let at: Timestamp
  public let value: Double

  public init(at: Timestamp, value: Double) {
    self.at = at
    self.value = value
  }
}

public struct SourceCandle: Hashable, Codable, Sendable {
  public let at: Timestamp
  public let open: Double
  public let high: Double
  public let low: Double
  public let close: Double

  public init(at: Timestamp, open: Double, high: Double, low: Double, close: Double) {
    self.at = at
    self.open = open
    self.high = high
    self.low = low
    self.close = close
  }
}

/// A record's values by field, such as `["price": 1.873, "premium": 0.159]`.
public typealias SourceRecord = [String: SourceValue]

/// What a source has now: the records it last got and when, and how it has gone since.
public struct SourceSnapshot: Hashable, Codable, Sendable {
  /// When the records were got.
  public let fetched: Timestamp
  /// When it was last tried, got or not.
  public let tried: Timestamp
  /// Fetches that failed one after another since `fetched`.
  public let failures: Int
  public let records: [String: SourceRecord]
  /// What `parse` kept for the next `requests`, such as the newest id it saw.
  public let state: JSONValue?
  /// Its script failing since `fetched`; `nil` while it works.
  public let breakage: SourceBreakage?

  /// Script failures in a row that make a source broken, to be mended in the background.
  public static let brokenAfter = 3

  public init(
    fetched: Timestamp, tried: Timestamp? = nil, failures: Int = 0, records: [String: SourceRecord],
    state: JSONValue? = nil, breakage: SourceBreakage? = nil
  ) {
    self.fetched = fetched
    self.tried = tried ?? fetched
    self.failures = failures
    self.records = records
    self.state = state
    self.breakage = breakage
  }

  /// The last try failed, so the records are older than they should be.
  public var isStale: Bool { failures > 0 }

  /// Its script failed `brokenAfter` times in a row; a new script is wanted.
  public var isBroken: Bool { (breakage?.failures ?? 0) >= Self.brokenAfter }

  /// The same records after one more failed try; `script` holds why when its script failed, not the network.
  public func failed(at moment: Timestamp, script: SourceProblems? = nil) -> SourceSnapshot {
    let breakage =
      script.map {
        SourceBreakage(since: breakage?.since ?? moment, failures: (breakage?.failures ?? 0) + 1, problems: $0.all)
      } ?? breakage
    return SourceSnapshot(
      fetched: fetched, tried: moment, failures: failures + 1, records: records, state: state, breakage: breakage)
  }

  public func value(_ field: SourceField) -> SourceValue? {
    records[field.record]?[field.field]
  }
}

/// How long a source's script has been failing.
public struct SourceBreakage: Hashable, Codable, Sendable {
  /// The first failure of this run of them.
  public let since: Timestamp
  public let failures: Int
  /// Why it failed the last time.
  public let problems: [SourceProblem]

  public init(since: Timestamp, failures: Int, problems: [SourceProblem]) {
    self.since = since
    self.failures = failures
    self.problems = problems
  }
}

/// How the text of a response is written; read from its `Content-Type` when not given.
public enum SourceEncoding: String, Hashable, Codable, Sendable {
  case utf8 = "utf-8"
  case gbk
}

/// A response as `parse` gets it: the text already decoded.
public struct SourceResponse: Hashable, Codable, Sendable {
  public let url: URL
  public let status: Int
  public let text: String

  public init(url: URL, status: Int, text: String) {
    self.url = url
    self.status = status
    self.text = text
  }
}

/// One fetch kept as it went, so `parse` can be run on it again without the network.
public struct SourceSample: Hashable, Codable, Sendable {
  /// The `now` `parse` was given.
  public let at: Timestamp
  public let state: JSONValue?
  public let requests: [SourceRequest]
  public let responses: [SourceResponse]

  public init(at: Timestamp, state: JSONValue?, requests: [SourceRequest], responses: [SourceResponse]) {
    self.at = at
    self.state = state
    self.requests = requests
    self.responses = responses
  }
}

/// What one run of a source got: the records and entries, what to keep for next time, and the sample to
/// replay.
public struct SourceResult: Hashable, Codable, Sendable {
  public let records: [String: SourceRecord]
  public let entries: [SourceEntry]
  public let state: JSONValue?
  public let sample: SourceSample

  public init(records: [String: SourceRecord], entries: [SourceEntry] = [], state: JSONValue?, sample: SourceSample) {
    self.records = records
    self.entries = entries
    self.state = state
    self.sample = sample
  }

  public init(_ output: SourceOutput, sample: SourceSample) {
    self.init(records: output.records, entries: output.entries, state: output.state, sample: sample)
  }
}

/// One thing wrong with a source or what its script gave, at the place where it is.
public struct SourceProblem: Hashable, Codable, Sendable, CustomStringConvertible {
  public let path: String
  public let reason: String

  public init(_ path: String, _ reason: String) {
    self.path = path
    self.reason = reason
  }

  public var description: String { path.isEmpty ? reason : "\(path): \(reason)" }
}

/// Why a source cannot be saved or a run of it failed: never empty.
public struct SourceProblems: Error, Hashable, Codable, Sendable {
  public let all: [SourceProblem]

  public init(all: [SourceProblem]) {
    self.all = all
  }

  public init(_ path: String, _ reason: String) {
    all = [SourceProblem(path, reason)]
  }
}
