import Foundation
import LociModel

/// Where a home's sources are kept under `agent/`: the chat's in `sources/`, a project's in
/// `projects/<id>/sources/`.
public struct DataSourceFolder: Hashable, Sendable {
  /// Relative to the `agent` folder.
  public let path: String

  public init(_ home: Home) {
    path = home.folder + "sources"
  }
}

/// `<folder>/<name>/source.json` is a source as Loci saved it with `loci source save`; beside it,
/// `samples/` keeps the newest fetches that worked, for `loci source test` to replay. Only the app writes
/// here.
extension Store {
  static let sourceFile = "source.json"
  static let samplesFolder = "samples"
  /// How many samples a source keeps.
  public static let samplesKept = 5

  /// Every source in the folder that can be read, by name.
  public func dataSources(in folder: DataSourceFolder) -> [DataSource] {
    subfolders(of: url(of: folder)).compactMap { dataSource(named: $0.lastPathComponent, in: folder) }
  }

  public func dataSource(named name: String, in folder: DataSourceFolder) -> DataSource? {
    try? decodeJSON(DataSource.self, at: sourceURL(name, in: folder).appending(path: Self.sourceFile))
  }

  /// Writes the source in place of the one there.
  public func saveDataSource(_ source: DataSource, in folder: DataSourceFolder) throws {
    try write(Formats.document(source), to: sourceURL(source.name, in: folder).appending(path: Self.sourceFile))
  }

  /// The samples the source keeps, newest first.
  public func samples(of name: String, in folder: DataSourceFolder) -> [SourceSample] {
    sampleFiles(of: name, in: folder).reversed().compactMap { try? decodeJSON(SourceSample.self, at: $0) }
  }

  /// Keeps the sample, and forgets the oldest past `samplesKept`.
  public func keepSample(_ sample: SourceSample, of name: String, in folder: DataSourceFolder) throws {
    let samples = sourceURL(name, in: folder).appending(path: Self.samplesFolder, directoryHint: .isDirectory)
    try write(Formats.document(sample), to: samples.appending(path: "\(sample.at.millisecondsSince1970).json"))
    for old in sampleFiles(of: name, in: folder).dropLast(Self.samplesKept) {
      try FileManager.default.removeItem(at: old)
    }
  }

  /// Oldest first, by the moment in their names.
  private func sampleFiles(of name: String, in folder: DataSourceFolder) -> [URL] {
    let samples = sourceURL(name, in: folder).appending(path: Self.samplesFolder, directoryHint: .isDirectory)
    return files(in: samples, withExtension: "json")
      .compactMap { url in Int64(url.deletingPathExtension().lastPathComponent).map { ($0, url) } }
      .sorted { $0.0 < $1.0 }
      .map(\.1)
  }

  private func url(of folder: DataSourceFolder) -> URL {
    agentFolder.appending(path: folder.path, directoryHint: .isDirectory)
  }

  private func sourceURL(_ name: String, in folder: DataSourceFolder) -> URL {
    url(of: folder).appending(path: name, directoryHint: .isDirectory)
  }
}
