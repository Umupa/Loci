import Foundation

public struct PiPackage: Hashable, Sendable {
  public enum Architecture: String, Hashable, Sendable {
    case arm64, x64
  }

  public let version: String
  public let url: URL
  public let sha256: String
  public let architecture: Architecture

  public var resign: Bool { architecture == .x64 }

  public init(version: String, url: URL, sha256: String, architecture: Architecture) {
    self.version = version
    self.url = url
    self.sha256 = sha256
    self.architecture = architecture
  }

  public static func official(arm: Bool) -> PiPackage {
    let version = "1.6.0"
    let architecture: Architecture = arm ? .arm64 : .x64
    return PiPackage(
      version: version,
      url: URL(
        string:
          "https://github.com/earendil-works/pi/releases/download/v\(version)/pi-darwin-\(architecture.rawValue).tar.gz"
      )!,
      sha256: arm
        ? "6429287b7ae98d726ec577815d14fd680e7c587e89ecc5153b4a145dc4adba33"
        : "5b69cd87c3b00e74cce2d1499df3b7a1ec73632f11abf64696d110f0f4dc4192",
      architecture: architecture)
  }

  public func unpack(_ archive: URL, into staging: URL, runner: any ProgramRunner) async throws(FetchError) -> URL {
    let file = archive.path(percentEncoded: false)
    let names = try await Self.run("/usr/bin/tar", ["-tzf", file], by: runner)
    let details = try await Self.run("/usr/bin/tar", ["-tvzf", file], by: runner)
    guard Self.allowedEntries(names, details: details) else {
      throw FetchError(reason: "The Pi archive has an entry outside its package or a link.")
    }
    _ = try await Self.run(
      "/usr/bin/tar",
      ["-xzf", file, "--no-same-owner", "--no-same-permissions", "-C", staging.path(percentEncoded: false)],
      by: runner)
    return staging.appending(path: "pi", directoryHint: .isDirectory)
  }

  public func checkSignature(of executable: URL, runner: any ProgramRunner) async throws(FetchError) {
    let path = executable.path(percentEncoded: false)
    if resign { _ = try await Self.run("/usr/bin/codesign", ["--force", "-s", "-", path], by: runner) }
    _ = try await Self.run("/usr/bin/codesign", ["--verify", "--strict", path], by: runner)
  }

  static func allowedEntries(_ names: String, details: String) -> Bool {
    let entries = names.split(separator: "\n")
    let types = details.split(separator: "\n").map(\.first)
    guard entries.count == types.count, Set(entries).count == entries.count else { return false }
    var executable = false
    for (entry, type) in zip(entries, types) {
      let path = entry.hasSuffix("/") ? entry.dropLast() : entry
      let parts = path.split(separator: "/", omittingEmptySubsequences: false)
      guard parts.first == "pi", parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
        !path.contains("\\"), type == "d" || (type == "-" && parts.count > 1 && !entry.hasSuffix("/"))
      else { return false }
      if path == "pi/pi", type == "-" { executable = true }
    }
    return executable
  }

  private static func run(_ executable: String, _ arguments: [String], by runner: any ProgramRunner)
    async throws(FetchError) -> String
  {
    let result: ProgramResult
    do throws(ProgramError) {
      result = try await runner.run(ProgramCall(executable: URL(filePath: executable), arguments: arguments))
    } catch {
      throw FetchError(reason: error.reason)
    }
    guard result.succeeded else { throw FetchError(reason: result.diagnostics) }
    return result.output
  }
}
