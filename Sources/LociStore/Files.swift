import Foundation
import LociModel

extension Store {
  func read(_ url: URL) throws -> Data {
    do {
      return try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      throw StoreError.notFound(relativePath(of: url))
    }
  }

  func readText(_ url: URL) throws -> String {
    guard let text = String(data: try read(url), encoding: .utf8) else {
      throw StoreError.invalid(FileProblem(path: relativePath(of: url), kind: .unreadable, reason: "not UTF-8 text"))
    }
    return text
  }

  /// Replaces the file in one step: a crash leaves either the old file or the new one, never half of it.
  func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  func decodeJSON<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value {
    let data = try read(url)
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw StoreError.invalid(problem(at: url, error))
    }
  }

  func decodeYAML<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value {
    let text = try readText(url)
    do {
      return try Formats.fromYAML(type, text)
    } catch {
      throw StoreError.invalid(problem(at: url, error))
    }
  }

  func problem(at url: URL, _ error: any Error) -> FileProblem {
    if case StoreError.invalid(let problem) = error { return problem }
    return FileProblem(path: relativePath(of: url), kind: .invalid, reason: Formats.reason(error))
  }

  func subfolders(of folder: URL) -> [URL] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
    return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  func files(in folder: URL, withExtension pathExtension: String) -> [URL] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    return entries.filter { $0.pathExtension == pathExtension }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  func discard(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
    try discard.remove(url)
  }
}
