import Foundation
import Testing

@testable import LociAgents

/// CN-S15: the app runs `gh` for the companion only with commands that read.
struct GitHubReadsTests {
  @Test(arguments: [
    ["pr", "view", "12", "-R", "o/r"], ["pr", "list", "--json", "title"], ["pr", "diff", "12"],
    ["pr", "checks", "12"], ["issue", "list", "--limit", "5"], ["issue", "view", "412"],
    ["run", "view", "123", "--log"], ["run", "list"], ["release", "view", "v0.9.0"], ["repo", "view", "o/r"],
    ["workflow", "list"], ["search", "issues", "snapshot restore"], ["label", "list"],
    ["api", "repos/o/r/pulls"], ["api", "repos/o/r", "--jq", ".stargazers_count"], ["api", "-X", "GET", "repos/o/r"],
    ["api", "--method=GET", "user"], ["api", "repos/o/r/issues", "--paginate"],
  ])
  func commandsThatOnlyReadRun(_ arguments: [String]) {
    #expect(GitHubReads.refusal(arguments) == nil)
  }

  @Test(arguments: [
    ["pr", "merge", "12"], ["pr", "comment", "12", "--body", "hi"], ["pr", "checkout", "12"], ["pr", "create"],
    ["issue", "close", "412"], ["issue", "create", "--title", "x"], ["repo", "delete", "o/r"],
    ["repo", "clone", "o/r"],
    ["release", "download", "v1"], ["run", "rerun", "123"], ["run", "download", "123"], ["workflow", "run", "ci"],
    ["auth", "token"], ["secret", "list"], ["pr", "view", "12", "--web"], ["issue", "list", "-w"],
    ["api", "-X", "POST", "repos/o/r/issues"], ["api", "--method", "DELETE", "repos/o/r"], ["api", "-XPATCH", "user"],
    ["api", "repos/o/r/issues", "-f", "title=x"], ["api", "repos/o/r/issues", "-Ftitle=x"],
    ["api", "repos/o/r", "--input", "body.json"], ["api", "repos/o/r", "--raw-field=a=b"], ["api", "graphql"],
    ["api", "repos/o/r", "-H", "X-HTTP-Method-Override: DELETE"], ["pr"], [], ["api"],
  ])
  func commandsThatCouldChangeSomethingAreRefusedWithAReason(_ arguments: [String]) {
    let refusal = GitHubReads.refusal(arguments)
    #expect(refusal != nil)
    #expect(refusal?.isEmpty == false)
  }

  @Test func aReadRunsGhWithoutAShellAndGivesBackWhatItPrinted() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try probeProgram("gh", in: folder)
    let launcher = ProbeLauncher(["gh run view 123 --log": .init(output: "build failed: test X\n")])
    let cli = GitHubCLI(launcher: launcher, search: AgentSearch(directories: [folder]))

    #expect(await cli.read(["run", "view", "123", "--log"]) == .output("build failed: test X\n"))
    #expect(await cli.read(["pr", "merge", "1"]) == .refused(GitHubReads.refusal(["pr", "merge", "1"]) ?? ""))
    #expect(launcher.launched == ["gh run view 123 --log"])
  }

  @Test func aGhThatFailsOrIsMissingSaysSo() async throws {
    let folder = try probeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let missing = GitHubCLI(launcher: ProbeLauncher(), search: AgentSearch(directories: [folder]))
    #expect(await missing.read(["pr", "list"]) == .failed("gh is not installed on this Mac"))

    try probeProgram("gh", in: folder)
    let failing = GitHubCLI(
      launcher: ProbeLauncher(["gh pr list": .init(output: "", status: 4)]), search: AgentSearch(directories: [folder]))
    #expect(await failing.read(["pr", "list"]) == .failed("gh stopped with status 4"))
  }
}
