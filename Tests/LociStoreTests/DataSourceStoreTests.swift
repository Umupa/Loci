import Foundation
import LociModel
import Testing

@testable import LociStore

/// DS-S1, DS-S3: a source's definition and samples on disk, its snapshot and history in the database.
struct DataSourceStoreTests {
  static let source = DataSource(
    name: "etf-premium", title: "ETF 溢价", every: SourceEvery(minutes: 1)!,
    window: SourceWindow("09:30-15:00", weekdays: true), script: "function requests() {}\nfunction parse() {}")
  static let home = SourceKey(.chat, "etf-premium")

  static func at(minutes: Int64) -> Timestamp {
    Timestamp(millisecondsSince1970: Fixture.instant.millisecondsSince1970 + minutes * 60_000)
  }

  static func sample(minutes: Int64) -> SourceSample {
    SourceSample(
      at: at(minutes: minutes), state: nil, requests: [.get(SourceGet(url: URL(string: "https://qt.gtimg.cn/q=a")!))],
      responses: [SourceResponse(url: URL(string: "https://qt.gtimg.cn/q=a")!, status: 200, text: "v=\(minutes)")])
  }

  @Test func aSourceIsKeptOnItsOwnersShelfAndReadsBack() throws {
    try withStore { store in
      try store.saveDataSource(Self.source, in: DataSourceFolder(.chat))

      #expect(
        FileManager.default.fileExists(atPath: store.root.appending(path: "agent/sources/etf-premium/source.json").path)
      )
      #expect(store.dataSources(in: DataSourceFolder(.chat)) == [Self.source])
      #expect(store.dataSource(named: "etf-premium", in: DataSourceFolder(.chat)) == Self.source)
      #expect(store.dataSource(named: "other", in: DataSourceFolder(.chat)) == nil)
    }
  }

  @Test func onlyTheNewestSamplesAreKeptNewestFirst() throws {
    try withStore { store in
      for minutes in 0..<7 {
        try store.keepSample(Self.sample(minutes: Int64(minutes)), of: "etf-premium", in: DataSourceFolder(.chat))
      }

      let samples = store.samples(of: "etf-premium", in: DataSourceFolder(.chat))

      #expect(samples.map(\.at) == (2..<7).reversed().map { Self.at(minutes: Int64($0)) })
    }
  }

  @Test func aFetchWritesTheSnapshotOverAndAddsItsNumbersToTheSeries() throws {
    let database = try StoreDatabase.inMemory()
    try database.recordFetch(
      Self.home, records: ["513870": ["premium": .number(0.15), "name": .text("纳指")]], state: nil,
      at: Self.at(minutes: 0))

    try database.recordFetch(
      Self.home, records: ["513870": ["premium": .number(0.16), "name": .text("纳指")]], state: .integer(3),
      at: Self.at(minutes: 1))

    let snapshot = try #require(try database.sourceSnapshot(Self.home))
    #expect(snapshot.records["513870"]?["premium"] == .number(0.16))
    #expect(snapshot.state == .integer(3))
    #expect(
      try database.sourceSeries(
        Self.home, field: SourceField("etf-premium.513870.premium")!, since: Self.at(minutes: 0))
        == [SourcePoint(at: Self.at(minutes: 0), value: 0.15), SourcePoint(at: Self.at(minutes: 1), value: 0.16)])
    #expect(
      try database.sourceSeries(
        Self.home, field: SourceField("etf-premium.513870.premium")!, since: Self.at(minutes: 1)
      )
      .count == 1)
  }

  @Test func aFailureKeepsTheRecordsAndMarksThemStaleUntilAFetchWorks() throws {
    let database = try StoreDatabase.inMemory()
    #expect(try database.recordFailure(Self.home, at: Self.at(minutes: 0)) == nil)
    try database.recordFetch(Self.home, records: ["a": ["v": .number(1)]], state: nil, at: Self.at(minutes: 1))

    try database.recordFailure(Self.home, at: Self.at(minutes: 2))
    let failed = try #require(try database.sourceSnapshot(Self.home))
    try database.recordFetch(Self.home, records: ["a": ["v": .number(2)]], state: nil, at: Self.at(minutes: 3))

    #expect(failed.isStale && failed.fetched == Self.at(minutes: 1) && failed.records["a"]?["v"] == .number(1))
    #expect(try database.sourceSnapshot(Self.home)?.isStale == false)
  }

  @Test func eachOwnersSourceIsItsOwn() throws {
    let database = try StoreDatabase.inMemory()
    try database.recordFetch(Self.home, records: ["a": ["v": .number(1)]], state: nil, at: Self.at(minutes: 0))

    let found = try database.sourceSnapshots([Self.home, SourceKey(.chat, "other")])

    #expect(Array(found.keys) == [Self.home])
  }

  @Test func historyOlderThanAWeekKeepsTheLastFetchOfEachHour() throws {
    let database = try StoreDatabase.inMemory()
    let field = SourceField("etf-premium.a.v")!
    for minute in stride(from: 0, to: 120, by: 30) {
      try database.recordFetch(
        Self.home, records: ["a": ["v": .number(Double(minute))]], state: nil, at: Self.at(minutes: Int64(minute)))
    }

    try database.recordFetch(
      Self.home, records: ["a": ["v": .number(-1)]], state: nil, at: Self.at(minutes: 8 * 24 * 60))

    let kept = try database.sourceSeries(Self.home, field: field, since: Self.at(minutes: 0)).map(\.value)
    #expect(kept.count == 3)
    #expect(kept.last == -1)
  }
}

/// DS-S7: the entries a source read, to tell new ones from those offered already.
struct SourceEntryStoreTests {
  static let home = SourceKey(.chat, "news")

  static func entry(_ id: String) -> SourceEntry { SourceEntry(id: id, title: "条目 \(id)") }

  @Test func onlyEntriesNotSeenBeforeAreNew() throws {
    let database = try StoreDatabase.inMemory()

    let first = try database.recordEntries(
      Self.home, [Self.entry("a"), Self.entry("b")], at: DataSourceStoreTests.at(minutes: 0))
    let second = try database.recordEntries(
      Self.home, [Self.entry("b"), Self.entry("c")], at: DataSourceStoreTests.at(minutes: 1))

    #expect(first.map(\.id) == ["a", "b"])
    #expect(second.map(\.id) == ["c"])
    #expect(
      try database.recordEntries(SourceKey(.chat, "other"), [Self.entry("a")], at: DataSourceStoreTests.at(minutes: 1))
        .count == 1)
  }

  @Test func entriesAreFoundInTheOrderTheyCameAndById() throws {
    let database = try StoreDatabase.inMemory()
    try database.recordEntries(Self.home, [Self.entry("a"), Self.entry("b")], at: DataSourceStoreTests.at(minutes: 0))
    try database.recordEntries(Self.home, [Self.entry("c")], at: DataSourceStoreTests.at(minutes: 0))

    let all = try database.sourceEntries(Self.home, after: nil, limit: 10)

    #expect(all.map(\.entry.id) == ["a", "b", "c"])
    #expect(try database.sourceEntries(Self.home, after: all[0].seq, limit: 1).map(\.entry.id) == ["b"])
    #expect(Set(try database.sourceEntries(Self.home, ids: ["a", "c", "z"]).map(\.entry.id)) == ["a", "c"])
  }

}
