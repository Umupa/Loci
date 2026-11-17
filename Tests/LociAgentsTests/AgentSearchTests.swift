import Foundation
import Testing

@testable import LociAgents

struct AgentSearchTests {
  @Test func thePathTheLoginShellPrintsIsSearchedFirst() async throws {
    let home = try probeFolder()
    let fromShell = try probeFolder()
    defer {
      try? FileManager.default.removeItem(at: home)
      try? FileManager.default.removeItem(at: fromShell)
    }
    try FileManager.default.createDirectory(
      at: home.appending(path: ".local/bin"), withIntermediateDirectories: true)
    _ = try probeProgram("claude", in: home.appending(path: ".local/bin"))
    let preferred = try probeProgram("claude", in: fromShell)
    let shell = ProbeLauncher(["zsh -lic printenv": .init(output: "PATH=\(fromShell.path)\n")])

    let search = await AgentSearch.forThisMac(
      launcher: shell, environment: ["SHELL": "/bin/zsh"], home: home)

    #expect(search.executable(named: ["claude"])?.path == preferred.path)
  }

  @Test func theFoldersInstallersUseAreSearchedWithoutTheShellListingThem() async throws {
    let home = try probeFolder()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(
      at: home.appending(path: ".npm-global/bin"), withIntermediateDirectories: true)
    let omp = try probeProgram("omp", in: home.appending(path: ".npm-global/bin"))
    let shell = ProbeLauncher(["zsh -lic printenv": .init(output: "PATH=/usr/bin:/bin\n")])

    let search = await AgentSearch.forThisMac(
      launcher: shell, environment: ["SHELL": "/bin/zsh"], home: home)

    #expect(search.executable(named: ["omp"])?.path == omp.path)
  }

  @Test func thePathThisProcessInheritedIsSearchedWhenTheShellDoesNotAnswer() async throws {
    let inherited = try probeFolder()
    let home = try probeFolder()
    defer {
      try? FileManager.default.removeItem(at: inherited)
      try? FileManager.default.removeItem(at: home)
    }
    let codex = try probeProgram("codex", in: inherited)
    let shell = ProbeLauncher(["zsh -lic printenv": .init(ends: false)])

    let search = await AgentSearch.forThisMac(
      launcher: shell, environment: ["SHELL": "/bin/zsh", "PATH": inherited.path], home: home,
      patience: .milliseconds(50))

    #expect(search.executable(named: ["codex"])?.path == codex.path)
  }

  @Test func aFolderListedTwiceIsSearchedOnce() async throws {
    let folder = try probeFolder()
    let home = try probeFolder()
    defer {
      try? FileManager.default.removeItem(at: folder)
      try? FileManager.default.removeItem(at: home)
    }
    let shell = ProbeLauncher([
      "zsh -lic printenv": .init(output: "PATH=\(folder.path):\(folder.path)\n")
    ])

    let search = await AgentSearch.forThisMac(
      launcher: shell, environment: ["SHELL": "/bin/zsh", "PATH": folder.path], home: home)

    #expect(search.directories.filter { $0.path == folder.path }.count == 1)
  }
}

struct AgentVersionTests {
  @Test(
    arguments: [
      ("0.62.0", "0.62.0"),
      ("v1.2.3", "v1.2.3"),
      ("codex-cli 0.20.0", "codex-cli 0.20.0"),
      ("1.2.3-beta.1", "1.2.3-beta.1"),
      ("0.62.0\n", "0.62.0"),
    ])
  func aWordThatLooksLikeAVersionIsKept(answer: String, expected: String) {
    #expect(AgentVersion.text(in: answer) == expected)
  }

  @Test(arguments: ["", "1.2", "1.2.3.4", "version one", "usage: grok [options]"])
  func anAnswerWithoutAVersionIsNotOne(answer: String) {
    #expect(AgentVersion.text(in: answer) == nil)
  }
}
