import Foundation
import LociModel
import Testing

@testable import LociTool

/// FO-S8: the companion follows a channel or show with `loci follow`, and sees who the person follows and what
/// they took in with `loci follow list`.
struct FollowToolTests {
  static let id = EntityID("019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e0f") ?? EntityID()
  static let item = EntityID("019a8f40-1b2c-7d3e-8f40-5a6b7c8d9e10") ?? EntityID()
  static let show = URL(string: "https://www.xiaoyuzhoufm.com/podcast/626b46ea9cbbf0451cf5a962")!
  static let follow = Follow(
    id: id, source: .xiaoyuzhou(podcast: "626b46ea9cbbf0451cf5a962", apple: nil), name: "张小珺Jùn｜商业访谈录",
    page: show, followed: Timestamp(millisecondsSince1970: 0))

  private static func json(_ value: some Encodable) -> Data {
    (try? Failure.encoding(value)) ?? Data()
  }

  private func tool(_ line: ScriptedLine) -> Tool {
    Tool(line: line, folder: URL(filePath: "/loci/agent/")) { _ in "" }
  }

  @Test func eachVerbIsReadWithItsArguments() throws {
    #expect(try Request.parse(["follow", Self.show.absoluteString]) == (.follow(.follow(Self.show)), false))
    #expect(try Request.parse(["follow", "list", "--json"]) == (.follow(.list), true))
  }

  @Test(arguments: [["follow"], ["follow", "张小珺"], ["follow", "list", "all"], ["follow", "a", "b"]])
  func aFollowCommandWrittenWrongSaysHowToWriteIt(_ words: [String]) {
    #expect(throws: UsageError(FollowRequest.usage)) { try Request.parse(words) }
  }

  @Test func followingSaysWhoIsFollowed() async {
    let line = ScriptedLine { _ in [.success(Self.json(Self.follow))] }

    let outcome = await tool(line).run(.follow(.follow(Self.show)), json: false)

    #expect(outcome == .worked("Following 张小珺Jùn｜商业访谈录 (\(Self.show.absoluteString))."))
    #expect(line.requests == [.command(name: AddFollow.name, body: Self.json(AddFollow(Self.show)))])
  }

  @Test func theListSaysTheNewestAndWhatIsInTheLibrary() async {
    let newest = Episode(title: "158. 复盘", link: URL(string: "https://www.xiaoyuzhoufm.com/episode/a")!)
    let listing = FollowListing(
      follow: Self.follow, latest: newest, kept: [FollowListing.Kept(item: Self.item, title: "157. 产品史")])
    let line = ScriptedLine { _ in [.success(Self.json([listing]))] }

    let outcome = await tool(line).run(.follow(.list), json: false)

    #expect(
      outcome
        == .worked(
          """
          张小珺Jùn｜商业访谈录  \(Self.show.absoluteString)
              newest: 158. 复盘  https://www.xiaoyuzhoufm.com/episode/a
              in the library: 157. 产品史  \(Self.item)
          """))
  }

  @Test func aFailureSaysWhy() async {
    let line = ScriptedLine { _ in [.failure(.host(.invalidRequest("Could not read it: the site refused this Mac.")))] }

    let outcome = await tool(line).run(.follow(.follow(Self.show)), json: false)

    #expect(outcome.status == 1)
  }

  @Test func helpSaysTheCompanionNeverTakesANewEpisodeIn() {
    let help = ToolGuide.topic("follow") ?? ""
    #expect(help.contains("loci follow list"))
    #expect(help.contains("Never save a new episode yourself"))
  }
}
