import Foundation
import LociModel
import Testing

@testable import LociAgents

struct AgentProbeTests {
  @Test func aProgramThatIsOnThePathIsReportedWithItsPathAndVersion() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let pi = try probeProgram("pi", in: folder)
    let probe = AgentProbe(
      launcher: ProbeLauncher(["pi --version": .init(output: "0.62.0\n")]),
      search: AgentSearch(directories: [folder]), workingDirectory: folder)

    let installation = try #require(await probe.installations().first { $0.provider == .pi })
    guard case .installed(let installed) = installation else {
      Issue.record("pi is installed in \(folder.path)")
      return
    }
    #expect(installed.executable == HostPath(pi))
    #expect(installed.version == "0.62.0")
    #expect(installed.signIn == .unknown)
  }

  @Test func aProgramTheProbeDoesNotFindIsMissing() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let probe = AgentProbe(
      launcher: ProbeLauncher(), search: AgentSearch(directories: [folder]), workingDirectory: folder)

    let installations = await probe.installations()
    #expect(installations.map(\.provider) == Provider.allCases.filter { $0 != .bundledPi })
    for installation in installations {
      guard case .missing = installation else {
        Issue.record("\(installation.provider) was found in an empty folder")
        continue
      }
    }
  }

  @Test func theInstallerNameIsPreferredOverTheShorterOne() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let named = try probeProgram("pi-coding-agent", in: folder)
    _ = try probeProgram("pi", in: folder)
    let probe = AgentProbe(
      launcher: ProbeLauncher(["pi-coding-agent --version": .init(output: "0.62.0")]),
      search: AgentSearch(directories: [folder]), workingDirectory: folder)

    let installation = try #require(await probe.installations().first { $0.provider == .pi })
    guard case .installed(let installed) = installation else {
      Issue.record("pi is installed in \(folder.path)")
      return
    }
    #expect(installed.executable == HostPath(named))
  }

  @Test func aProgramInstalledAsALinkIsFound() async throws {
    let folder = try probeFolder()
    let installed = try probeFolder()
    defer {
      try? FileManager.default.removeItem(at: folder)
      try? FileManager.default.removeItem(at: installed)
    }
    let target = installed.appending(path: "claude-2.1.326")
    try probeProgram("claude-2.1.326", in: installed)
    try FileManager.default.createSymbolicLink(at: folder.appending(path: "claude"), withDestinationURL: target)
    let probe = AgentProbe(
      launcher: ProbeLauncher(["claude --version": .init(output: "2.1.326 (Claude Code)")]),
      search: AgentSearch(directories: [folder]), workingDirectory: folder)

    let installation = try #require(await probe.installations().first { $0.provider == .claudeCode })
    guard case .installed(let installedProgram) = installation else {
      Issue.record("the Claude Code CLI is linked in \(folder.path)")
      return
    }
    #expect(installedProgram.executable == HostPath(folder.appending(path: "claude")))
    #expect(installedProgram.version == "2.1.326 (Claude Code)")
  }

  @Test func aFileThatIsNotExecutableIsNotAProgram() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try probeProgram("hermes", in: folder, executable: false)
    let probe = AgentProbe(
      launcher: ProbeLauncher(), search: AgentSearch(directories: [folder]), workingDirectory: folder)

    let installation = try #require(await probe.installations().first { $0.provider == .hermes })
    #expect(installation == .missing(.hermes))
  }

  @Test func aProgramThatPrintsNoVersionIsStillInstalled() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try probeProgram("grok", in: folder)
    let probe = AgentProbe(
      launcher: ProbeLauncher(["grok --version": .init(output: "usage: grok [options]\n")]),
      search: AgentSearch(directories: [folder]), workingDirectory: folder)

    let installation = try #require(await probe.installations().first { $0.provider == .grok })
    guard case .installed(let installed) = installation else {
      Issue.record("grok is installed in \(folder.path)")
      return
    }
    #expect(installed.version == nil)
  }

  @Test func aProgramThatDoesNotAnswerLeavesTheProbeWithoutAVersion() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try probeProgram("opencode", in: folder)
    let launcher = ProbeLauncher(["opencode --version": .init(output: "partial", ends: false)])
    let probe = AgentProbe(
      launcher: launcher, search: AgentSearch(directories: [folder]), workingDirectory: folder,
      patience: .milliseconds(50))

    let installation = try #require(await probe.installations().first { $0.provider == .opencode })
    guard case .installed(let installed) = installation else {
      Issue.record("opencode is installed in \(folder.path)")
      return
    }
    #expect(installed.version == nil)
    #expect(launcher.launched.filter { $0 == "opencode --version" }.count == 1)
  }

  @Test func everyExternalProviderHasAProgramToLookFor() {
    #expect(AgentCLI.all.map(\.provider) == Provider.allCases.filter { $0 != .bundledPi })
  }
}

func probeFolder() throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appending(path: "loci-probe-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder
}

@discardableResult
func probeProgram(_ name: String, in folder: URL, executable: Bool = true) throws -> URL {
  let path = folder.appending(path: name)
  try Data("#!/bin/sh\n".utf8).write(to: path)
  if executable {
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
  }
  return path
}
