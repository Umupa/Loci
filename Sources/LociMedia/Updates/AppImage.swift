import Foundation
import LociModel

/// The programs that take a copy of Loci out of a downloaded disk image, zip or patch and start it:
/// `hdiutil`, `ditto`, `bspatch`, `codesign` and `open`.
public struct AppImage: Sendable {
  private let runner: any ProgramRunner
  private let opener: String

  public init(runner: any ProgramRunner, opener: String = "/usr/bin/open") {
    self.runner = runner
    self.opener = opener
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

  /// Unpacks the zip `archive` into `folder`.
  public func expand(_ archive: URL, into folder: URL) async throws(FetchError) {
    try await succeed(
      "/usr/bin/ditto", ["-x", "-k", archive.plainPath, folder.plainPath], or: "the download could not be unpacked")
  }

  /// Writes `new`, the file `diff` rebuilds from `old`, with the `bspatch` macOS ships.
  public func rebuild(_ old: URL, into new: URL, with diff: URL) async throws(FetchError) {
    try await succeed(
      "/usr/bin/bspatch", [old.plainPath, new.plainPath, diff.plainPath], or: "the patch could not be applied")
  }

  /// Opens `app` once the process `waitingFor` has ended, so the new copy starts after this one quits.
  public func open(_ app: URL, after waitingFor: Int32) async throws(FetchError) {
    let script = "while kill -0 \(waitingFor) 2>/dev/null; do sleep 0.2; done; \(opener) \"$0\""
    try await succeed(
      "/bin/sh", ["-c", "(\(script)) </dev/null >/dev/null 2>&1 &", app.plainPath],
      or: "the new copy could not be opened")
  }

  /// Watches the copy just put at `app` start, apart from this process, once the process `waitingFor` has
  /// ended: opens it first when `opens`, then waits up to `appearing` for it to run. Once `previous.started`
  /// is written the previous copy is removed. When the new copy quits before that, or an opened one never
  /// runs, it is moved to `previous.failed`, the previous copy goes back in its place and opens, and the
  /// release is recorded in `previous.record`. A copy still starting is never stopped.
  public func watchStart(
    of app: URL, previous: PreviousCopy, after waitingFor: Int32, opens: Bool, appearing: Duration
  ) async throws(FetchError) {
    let paths = [
      app, previous.folder, previous.app, previous.release, previous.started, previous.failed, previous.record,
    ]
    let arguments =
      paths.map(\.barePath) + [
        opens ? "yes" : "no",
        String(max(Int(appearing.components.seconds) * 2, 1)), String(waitingFor), opener,
      ]
    try await succeed(
      "/bin/sh", ["-c", "(\(Self.watcher)) </dev/null >/dev/null 2>&1 &", "watch"] + arguments,
      or: "the new copy could not be watched")
  }

  private static let watcher = """
    app="$1"; folder="$2"; previous="$3"; release="$4"; started="$5"; failed="$6"; record="$7"; opens="$8"; \
    halves="$9"; shift 9; pid="$1"; opener="$2"; \
    running() { ps -axo comm= | grep -F -q -- "$app/Contents/MacOS/"; }; \
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done; \
    if [ "$opens" = yes ]; then "$opener" "$app"; fi; \
    waited=0; \
    until running || [ -e "$started" ]; do \
      sleep 0.5; waited=$((waited + 1)); \
      if [ "$waited" -ge "$halves" ]; then [ "$opens" = yes ] && break; exit 0; fi; \
    done; \
    while [ ! -e "$started" ] && running; do sleep 0.5; done; \
    if [ -e "$started" ]; then rm -rf "$folder"; exit 0; fi; \
    rm -rf "$failed"; \
    mv "$app" "$failed" && mv "$previous" "$app" && mv "$release" "$record" && rm -rf "$folder" && "$opener" "$app"
    """

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
  /// The path without a trailing slash, so the shell can join it with more.
  fileprivate var barePath: String {
    let path = plainPath
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
