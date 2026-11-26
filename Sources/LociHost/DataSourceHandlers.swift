import Foundation
import LociMedia
import LociModel
import LociStore

/// `loci source`: a home's sources, kept in its `sources/` folder (the chat's `agent/sources/`, a project's
/// `agent/projects/<id>/sources/`), fetched by the app with no model in the way.
extension LocalHost {
  public func saveDataSource(_ command: SaveDataSource) async throws(HostError) -> SourceOutcome {
    let problems = DataSourceCheck.problems(in: command.source)
    guard problems.isEmpty else { return .failed(SourceProblems(all: problems)) }
    return try await sourceKeeper.save(command.source, in: command.home)
  }

  /// A repair's save: the source it was granted, in its home. The new script must read every sample the
  /// source failed on, and it is kept only while the repair's grant is open and the definition it mends is
  /// still the saved one and still broken.
  func saveDataSource(_ source: DataSource, repairing grant: RepairGrant) async throws(HostError) -> SourceOutcome {
    let problems = DataSourceCheck.problems(in: source)
    guard problems.isEmpty else { return .failed(SourceProblems(all: problems)) }
    guard source.name == grant.source.name else {
      throw .invalidRequest("This repair mends only the source \(grant.source.name); use that one.")
    }
    let home = grant.source.home
    let folder = DataSourceFolder(home)
    let store = store
    let database = database
    let commits = sourceKeeper.commits
    let runner = environment.media.dataSources
    let saving = SourceKeeper.Saving(
      check: { _ in
        guard await commits.isOpen(grant) else { return nil }
        let since =
          ((try? database.sourceSnapshot(grant.source)) ?? nil)?.breakage?.since ?? Timestamp(millisecondsSince1970: 0)
        var found: [SourceProblem] = []
        for sample in store.samples(of: source.name, in: folder) where sample.at >= since {
          do throws(SourceProblems) {
            _ = try await runner.replay(sample, script: source.script)
          } catch {
            found += error.all.map { SourceProblem("sample \(sample.at)", $0.description) }
          }
        }
        return found.isEmpty ? nil : SourceProblems(all: found)
      },
      still: {
        store.dataSource(named: source.name, in: folder) == grant.broken
          && ((try? database.sourceSnapshot(grant.source)) ?? nil)?.isBroken == true
      },
      grant: grant, refusal: "The source changed or works again since this repair began; nothing was saved.")
    return try await sourceKeeper.save(source, in: home, saving: saving)
  }

  public func pickPanelEntries(_ command: PickPanelEntries) async throws(HostError) -> Done {
    try await panels.pick(command, in: command.home, from: nil)
    return Done()
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
    try await dataSources(of: home, named: nil)
  }

  /// The home's sources; only `named`, when given.
  func dataSources(of home: Home, named: String?) async throws(HostError) -> [DataSourceEntry] {
    let folder = DataSourceFolder(home)
    return try attempt {
      try store.dataSources(in: folder).filter { named == nil || $0.name == named }.map { source in
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
