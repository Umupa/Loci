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
    #expect(try Request.parse([]) == (.help, false))
    #expect(try Request.parse(["help"]) == (.help, false))
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
