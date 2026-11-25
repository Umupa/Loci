import Foundation

/// A source as `loci source` shows it: its definition, what it has now, and how many samples it keeps.
public struct DataSourceEntry: Hashable, Codable, Sendable {
  public let source: DataSource
  public let snapshot: SourceSnapshot?
  public let samples: Int

  public init(source: DataSource, snapshot: SourceSnapshot?, samples: Int) {
    self.source = source
    self.snapshot = snapshot
    self.samples = samples
  }
}

/// How a run of a source went: the records it got, or why it got none.
public enum SourceOutcome: Hashable, Codable, Sendable {
  case records([String: SourceRecord])
  case failed(SourceProblems)
}

/// Fetches the source once for real and keeps it only when that works: the definition, the sample, and
/// the records as its first snapshot. Refused with the problems when it does not. The app puts it in the home
/// of the session the command came from.
public struct SaveDataSource: LocalToolCommand {
  public static let name = "sources.save"
  public let source: DataSource
  public let project: Project.ID?

  public init(_ source: DataSource, in home: Home = .chat) {
    self.source = source
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> SourceOutcome {
    try await handler.saveDataSource(self)
  }
}

/// Runs `parse` on the samples a source keeps, newest first, with its own script or `script` in its place.
/// Nothing is fetched and nothing is written.
public struct TestDataSource: LocalToolCommand {
  public static let name = "sources.test"
  public let source: String
  public let script: String?
  public let project: Project.ID?

  public init(_ source: String, script: String? = nil, in home: Home = .chat) {
    self.source = source
    self.script = script
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [SourceReplay] {
    try await handler.testDataSource(self)
  }
}

/// One sample run again.
public struct SourceReplay: Hashable, Codable, Sendable {
  /// When the sample was fetched.
  public let at: Timestamp
  public let outcome: SourceOutcome

  public init(at: Timestamp, outcome: SourceOutcome) {
    self.at = at
    self.outcome = outcome
  }
}

/// Every source of a home, by name.
public struct ListDataSources: LocalToolCommand {
  public static let name = "sources.list"
  public let project: Project.ID?

  public init(of home: Home = .chat) {
    project = home.project
  }

  public var home: Home { Home(project) }

  public func run(on handler: any CommandHandler) async throws(HostError) -> [DataSourceEntry] {
    try await handler.dataSources(of: home)
  }
}

/// What a chart draws for one field: the points within a span, or the newest candles. `nil` until the
/// source has something for it.
public struct WatchSourceHistory: Subscription {
  public static let name = "sources.history"
  public let source: SourceKey
  public let field: SourceField
  /// The span a line is cut to; `nil` for candles.
  public let range: PanelRange?

  public init(_ source: SourceKey, field: SourceField, range: PanelRange?) {
    self.source = source
    self.field = field
    self.range = range
  }

  public func value(from handler: any CommandHandler) async throws(HostError) -> SourceHistory? {
    try await handler.sourceHistory(self)
  }

  public func isAffected(by changes: Set<ContentChange>) -> Bool {
    changes.contains { change in
      switch change {
      case .source(let key): key == source
      case .everything: true
      case .item, .course, .courseActivity, .notes, .reading, .job, .media, .conversation, .turnEnded, .review,
        .loci, .runtime, .timers, .connectors, .projects:
        false
      }
    }
  }
}
