import Foundation
import LociModel

/// The programs that take a copy of Loci out of a downloaded disk image and start it: `hdiutil`, `codesign`,
/// `ditto` and `open`.
public struct AppImage: Sendable {
  private let runner: any ProgramRunner

  public init(runner: any ProgramRunner) {
    self.runner = runner
  }

  /// Attaches `image` read-only at `mountPoint`, without showing it in the Finder.
  public func mount(_ image: URL, at mountPoint: URL) async throws(FetchError) {
    try await succeed(
      "/usr/bin/hdiutil",
      ["attach", "-nobrowse", "-noautoopen", "-readonly", "-mountpoint", mountPoint.plainPath, image.plainPath],
      or: "the disk image could not be opened")
  }

  public func unmount(_ mountPoint: URL) async {
    _ = try? await runner.run(
      ProgramCall(executable: URL(filePath: "/usr/bin/hdiutil"), arguments: ["detach", "-force", mountPoint.plainPath]))
  }

  /// The code requirement every later copy must meet: the same bundle id signed by the same certificate. A
  /// copy signed ad hoc has none, since no other copy could meet it.
  public func requirement(of app: URL) async throws(FetchError) -> String {
    let result = try await run("/usr/bin/codesign", ["-d", "-r-", app.plainPath])
    let prefix = "designated => "
    guard result.succeeded, let line = result.output.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }),
      !line.dropFirst(prefix.count).hasPrefix("cdhash")
    else { throw FetchError(reason: "this copy of Loci is not signed with a certificate") }
    return String(line.dropFirst(prefix.count))
  }

  /// Fails unless `app` is intact and signed so that it meets `requirement`.
  public func verify(_ app: URL, meets requirement: String) async throws(FetchError) {
    try await succeed(
      "/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(requirement)", app.plainPath],
      or: "the new copy is not signed like this one")
  }

  /// Copies `app` to `destination`, keeping its signature and attributes.
  public func copy(_ app: URL, to destination: URL) async throws(FetchError) {
    try await succeed("/usr/bin/ditto", [app.plainPath, destination.plainPath], or: "the new copy could not be copied")
  }

  /// Opens `app` once the process `waitingFor` has ended, so the new copy starts after this one quits.
  public func open(_ app: URL, after waitingFor: Int32) async throws(FetchError) {
    let script = "while kill -0 \(waitingFor) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\""
    try await succeed(
      "/bin/sh", ["-c", "(\(script)) </dev/null >/dev/null 2>&1 &", app.plainPath],
      or: "the new copy could not be opened")
  }

  private func succeed(_ program: String, _ arguments: [String], or failure: String) async throws(FetchError) {
    let result = try await run(program, arguments)
    guard result.succeeded else {
      let said = result.diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
      throw FetchError(reason: said.isEmpty ? failure : "\(failure): \(said)")
    }
  }

  private func run(_ program: String, _ arguments: [String]) async throws(FetchError) -> ProgramResult {
    do {
      return try await runner.run(ProgramCall(executable: URL(filePath: program), arguments: arguments))
    } catch {
      throw FetchError(reason: error.reason)
    }
  }
}

extension URL {
  fileprivate var plainPath: String { path(percentEncoded: false) }
}
