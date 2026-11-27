import Foundation
import LociMedia
import LociModel
import Synchronization

/// Answers for `codesign`, `hdiutil`, `ditto`, `bspatch` and `sh`. Copying the app writes a new copy whose marker
/// says `new`. An archive unpacks to the files the JSON object in it names, path to contents; a diff holds the
/// file it rebuilds.
final class UpdatePrograms: ProgramRunner {
  private let recorded = Mutex<[ProgramCall]>([])
  private let passes: Mutex<Bool>
  private let patching = Mutex(true)
  let signature: String

  init(signature: String, verifies: Bool) {
    self.signature = signature
    passes = Mutex(verifies)
  }

  var calls: [ProgramCall] { recorded.withLock { $0 } }

  /// Every place the programs were asked to write: what `ditto` unpacks or copies into, where `bspatch`
  /// writes, and where `hdiutil` mounts.
  var writtenPaths: [String] {
    calls.compactMap { call in
      switch (call.executable.lastPathComponent, call.arguments.first) {
      case ("ditto", "-x"): call.arguments[3]
      case ("ditto", _): call.arguments[1]
      case ("bspatch", _): call.arguments[1]
      case ("hdiutil", "attach"): call.arguments.firstIndex(of: "-mountpoint").map { call.arguments[$0 + 1] }
      default: nil
      }
    }
  }

  var rebuilds: Bool {
    get { patching.withLock { $0 } }
    set { patching.withLock { $0 = newValue } }
  }

  /// An archive that unpacks to `files`, each path to its contents.
  static func archive(_ files: [String: String]) -> Data {
    (try? JSONEncoder().encode(files)) ?? Data()
  }

  var verifies: Bool {
    get { passes.withLock { $0 } }
    set { passes.withLock { $0 = newValue } }
  }

  func run(_ call: ProgramCall, line: @escaping @Sendable (String) -> Void) async throws(ProgramError)
    -> ProgramResult
  {
    recorded.withLock { $0.append(call) }
    switch (call.executable.lastPathComponent, call.arguments.first) {
    case ("codesign", "-d"):
      return ProgramResult(status: 0, output: "designated => \(signature)\n")
    case ("codesign", "--verify"):
      return verifies ? ProgramResult(status: 0, output: "") : ProgramResult(status: 3, output: "", diagnostics: "nope")
    case ("ditto", "-x"):
      let folder = URL(filePath: call.arguments[3])
      let data = (try? Data(contentsOf: URL(filePath: call.arguments[2]))) ?? Data()
      guard let files = try? JSONDecoder().decode([String: String].self, from: data) else {
        return ProgramResult(status: 1, output: "", diagnostics: "not an archive")
      }
      for (path, contents) in files {
        let file = folder.appending(path: path)
        try? FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(contents.utf8).write(to: file)
      }
      return ProgramResult(status: 0, output: "")
    case ("bspatch", _):
      guard rebuilds, let diff = try? Data(contentsOf: URL(filePath: call.arguments[2])) else {
        return ProgramResult(status: 1, output: "", diagnostics: "corrupt patch")
      }
      try? diff.write(to: URL(filePath: call.arguments[1]))
      return ProgramResult(status: 0, output: "")
    case ("ditto", _):
      let copy = URL(filePath: call.arguments[1])
      try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
      try? Data("new".utf8).write(to: copy.appending(path: "marker"))
      return ProgramResult(status: 0, output: "")
    default:
      return ProgramResult(status: 0, output: "")
    }
  }
}
