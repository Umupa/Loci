import Foundation
import LociModel
import Testing

@testable import LociTool

struct RequestTests {
  private let id = "019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f"

  @Test func eachVerbIsReadWithItsArguments() throws {
    let item = try #require(EntityID(id))
    #expect(try Request.parse(["search", "raft", "term"]) == (.search("raft term"), false))
    #expect(try Request.parse(["show", id]) == (.show(item), false))
    #expect(try Request.parse(["wait", id, "--json"]) == (.wait(item), true))
    #expect(
      try Request.parse(["save", "https://example.com/a"]) == (
        .save(try #require(URL(string: "https://example.com/a"))), false
      ))
    #expect(
      try Request.parse(["import", "a.md", "--title", "Borg"]) == (.importFile(path: "a.md", title: "Borg"), false))
    #expect(try Request.parse(["import", "talk.mp4"]) == (.importFile(path: "talk.mp4", title: nil), false))
    #expect(try Request.parse([]) == (.help(nil), false))
    #expect(try Request.parse(["help"]) == (.help(nil), false))
  }

  @Test func sourceCommandsTakeAWebLinkAndAnOptionalFullCommit() throws {
    let link = "https://example.com/owner/repo"
    let url = try #require(URL(string: link))
    let sha = String(repeating: "a", count: 40)
    let commit = try #require(CommitID(sha))
    #expect(try Request.parse(["read", link]) == (.read(url), false))
    #expect(try Request.parse(["repo", link]) == (.repo(url, commit: nil), false))
    #expect(try Request.parse(["repo", link, "--commit", sha, "--json"]) == (.repo(url, commit: commit), true))
  }

  @Test(arguments: [
    ["read"], ["read", "https://person@example.com/private"], ["read", "file:///paper.pdf"],
    ["read", "https://example.com", "extra"],
    ["repo"], ["repo", "https://example.com", "--commit"], ["repo", "https://example.com", "--commit", "deadbee"],
    ["repo", "https://person@example.com/repo"], ["repo", "git@example.com:repo"],
  ])
  func invalidSourceArgumentsExitWithTwo(arguments: [String]) async {
    let result = await LociCommand.run(arguments, environment: [:], folder: URL(filePath: "/"))
    #expect(result.status == 2)
  }

  @Test(arguments: [
    ["search"], ["show"], ["show", "not-an-id"], ["wait", "a", "b"], ["save", "example.com"], ["save", "ftp://x/y"],
    ["import"], ["import", "a.md", "--title"], ["import", "talk.mp4", "--title", "Talk"], ["delete", "x"],
  ])
  func aCommandWrittenWrongSaysHowToWriteIt(arguments: [String]) {
    #expect(throws: UsageError.self) { try Request.parse(arguments) }
  }

  @Test func helpNeedsNoApp() async {
    let outcome = await LociCommand.run(["help"], environment: [:], folder: URL(filePath: "/"))
    #expect(outcome == .worked(ToolGuide.text))
    #expect(outcome.text.contains("loci read <url>"))
    #expect(outcome.text.contains("loci repo <url> [--commit <sha>]"))
  }

  @Test func outsideALociSessionItSaysSo() async {
    let outcome = await LociCommand.run(["search", "raft"], environment: [:], folder: URL(filePath: "/"))
    #expect(outcome.status == 1)
    #expect(outcome.text.contains(LocalCall.socketVariable))
  }

  @Test func aWrongCommandExitsWithTwo() async {
    let outcome = await LociCommand.run(["fetch"], environment: [:], folder: URL(filePath: "/"))
    #expect(outcome.status == 2)
  }
}
