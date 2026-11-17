import Foundation
import Testing

enum Repository {
  static let root = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  static func directories(in folder: String) throws -> [String] {
    try FileManager.default
      .contentsOfDirectory(at: root.appending(path: folder), includingPropertiesForKeys: [.isDirectoryKey])
      .filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
      .map(\.lastPathComponent)
      .sorted()
  }

  static func files(in folder: String) throws -> [SourceFile] {
    try directories(in: folder).flatMap { module -> [SourceFile] in
      let base = root.appending(path: folder).appending(path: module)
      guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
      return try walker.compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.path < $1.path }
        .map { url in
          let path = String(url.path.dropFirst(root.path.count + 1))
          return SourceFile(path: path, module: module, text: try String(contentsOf: url, encoding: .utf8))
        }
    }
  }
}

struct Violation: CustomStringConvertible {
  let file: String
  let line: Int
  let found: String
  let fix: String

  var description: String { "\(file):\(line): \(found)\n  → \(fix)" }
}

func report(_ violations: [Violation]) {
  for violation in violations {
    Issue.record("\(violation)")
  }
}
