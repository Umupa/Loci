import Foundation
import LociMedia
import LociModel
import LociStore

/// `loci source`: a home's sources, kept in its `sources/` folder (the chat's `agent/sources/`, a project's
/// `agent/projects/<id>/sources/`), fetched by the app with no model in the way.
extension LocalHost {
  public func saveDataSource(_ command: SaveDataSource) async throws(HostError) -> SourceOutcome {
    let home = command.home
    let source = command.source
    let problems = DataSourceCheck.problems(in: source)
    guard problems.isEmpty else { return .failed(SourceProblems(all: problems)) }
    let key = SourceKey(home, source.name)
    let state = try attempt { try database.sourceSnapshot(key)?.state }
    let result: SourceResult
    do throws(SourceProblems) {
      result = try await environment.media.dataSources.fetch(source, state: state, now: environment.now())
    } catch {
      return .failed(error)
    }
    let folder = DataSourceFolder(home)
    try attempt {
      try store.saveDataSource(source, in: folder)
      try store.keepSample(result.sample, of: source.name, in: folder)
      try database.recordFetch(key, records: result.records, state: result.state, at: result.sample.at)
    }
    await follow([.source(key)])
    return .records(result.records)
  }

  public func testDataSource(_ command: TestDataSource) async throws(HostError) -> [SourceReplay] {
    let folder = DataSourceFolder(command.home)
    guard let source = store.dataSource(named: command.source, in: folder) else {
      throw .notFound("source \(command.source)")
    }
    var replays: [SourceReplay] = []
    for sample in store.samples(of: source.name, in: folder) {
      do throws(SourceProblems) {
        let result = try await environment.media.dataSources.replay(sample, script: command.script ?? source.script)
        replays.append(SourceReplay(at: sample.at, outcome: .records(result.records)))
      } catch {
        replays.append(SourceReplay(at: sample.at, outcome: .failed(error)))
      }
    }
    return replays
  }

  public func dataSources(of home: Home) async throws(HostError) -> [DataSourceEntry] {
    let folder = DataSourceFolder(home)
    return try attempt {
      try store.dataSources(in: folder).map { source in
        DataSourceEntry(
          source: source, snapshot: try database.sourceSnapshot(SourceKey(home, source.name)),
          samples: store.samples(of: source.name, in: folder).count)
      }
    }
  }

  public func sourceHistory(_ subscription: WatchSourceHistory) async throws(HostError) -> SourceHistory? {
    let source = subscription.source
    let field = subscription.field
    guard let snapshot = try attempt({ try database.sourceSnapshot(source) }) else { return nil }
    switch (snapshot.value(field), subscription.range) {
    case (.points(let points), let range?):
      return .points(SourceHistory.cut(points, to: range))
    case (.candles(let candles), _):
      return .candles(Array(candles.sorted { $0.at < $1.at }.suffix(SourceHistory.mostCandles)))
    case (.number, let range?):
      let since = Timestamp(millisecondsSince1970: snapshot.fetched.millisecondsSince1970 - range.milliseconds)
      return .points(
        SourceHistory.cut(try attempt { try database.sourceSeries(source, field: field, since: since) }, to: range))
    case (.points, nil), (.number, nil), (.text, _), (nil, _):
      return nil
    }
  }

  /// The snapshots of the sources a home's panels point at, and those of the project panels pinned with them.
  func readings(of panels: [Panel], in home: Home, pinned: [PanelPlace: Panel] = [:]) -> PanelReadings {
    var sources = panels.reduce(into: Set<SourceKey>()) { $0.formUnion($1.sources(of: home)) }
    for case (.pinned(let project, _), let panel) in pinned { sources.formUnion(panel.sources(of: .project(project))) }
    guard !sources.isEmpty else { return PanelReadings() }
    return PanelReadings((try? database.sourceSnapshots(sources)) ?? [:])
  }
}
