import Foundation
import LociModel

public struct GitRepository: Sendable {
  private let runner: any ProgramRunner
  private let executable: URL
  private let proxy: String?

  public init(runner: any ProgramRunner, executable: URL, proxy: String? = nil) {
    self.runner = runner
    self.executable = executable
    self.proxy = proxy
  }

  public func head(of url: URL) async throws(FetchError) -> CommitID {
    let output = try await run(["ls-remote", "--", url.absoluteString, "HEAD"])
    for line in output.split(whereSeparator: \.isNewline) {
      let fields = line.split(separator: "\t")
      if fields.count == 2, fields[1] == "HEAD", let commit = CommitID(String(fields[0])) {
        return commit
      }
    }
    throw FetchError(reason: "The repository has no default commit.")
  }

  public func checkout(_ url: URL, commit: CommitID, into folder: URL) async throws(FetchError) {
    let path = folder.path(percentEncoded: false)
    let objectFormat = commit.description.count == 64 ? "sha256" : "sha1"
    _ = try await run(["init", "--quiet", "--template=", "--object-format=\(objectFormat)", path])
    let there = ["-C", path]
    _ = try await run(there + ["fetch", "--depth=1", "--no-tags", "--", url.absoluteString, commit.description])
    _ = try await run(there + ["checkout", "--quiet", "--detach", commit.description, "--"])
    let head = try await run(there + ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard head == commit.description else { throw FetchError(reason: "Git checked out a different commit.") }
  }

  private func run(_ arguments: [String]) async throws(FetchError) -> String {
    var environment = [
      "PATH": "/usr/bin:/bin",
      "LC_ALL": "C",
      "GIT_TERMINAL_PROMPT": "0",
      "GIT_CONFIG_NOSYSTEM": "1",
      "GIT_CONFIG_GLOBAL": "/dev/null",
      "GIT_ALLOW_PROTOCOL": "http:https",
    ]
    if let proxy {
      environment["http_proxy"] = proxy
      environment["https_proxy"] = proxy
    }
    let options = [
      "-c", "core.hooksPath=/dev/null", "-c", "core.symlinks=false", "-c", "maintenance.auto=false",
    ]
    let result: ProgramResult
    do {
      result = try await runner.run(
        .init(executable: executable, arguments: options + arguments, environment: environment))
    } catch {
      throw FetchError(reason: "Git could not start at \(executable.path(percentEncoded: false)): \(error.reason)")
    }
    guard !Task.isCancelled else { throw FetchError(reason: "The repository fetch was cancelled.") }
    guard result.succeeded else {
      let diagnostic = result.diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
      let message = diagnostic.lowercased()
      if message.contains("repository not found") || message.contains("terminal prompts disabled") {
        throw FetchError(reason: "The repository was not found or is private.")
      }
      let reason = diagnostic.isEmpty ? "Git exited with status \(result.status)." : diagnostic
      throw FetchError(reason: reason)
    }
    return result.output
  }
}
