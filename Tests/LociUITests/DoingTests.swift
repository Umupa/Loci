import Foundation
import LociModel
import Testing

@testable import LociUI

struct DoingTests {
  private static func message(_ body: Message.Body) -> Message {
    Message(id: EntityID(), at: Timestamp(millisecondsSince1970: 0), body: body)
  }

  private static func tool(
    _ kind: ToolActivity.Kind, _ subject: String?, name: String = "tool", state: ToolActivity.State = .running
  ) -> Message {
    message(.tool(ToolActivity(id: "t", name: name, kind: kind, subject: subject, output: "", state: state)))
  }

  private static func doing(_ messages: Message...) -> Doing {
    Doing(messages)
  }

  @Test func activityLabelsStayInEnglishWhenTheAppIsInChinese() {
    let activities: [Doing] = [
      .thinking, .searching("raft"), .site("github.com"), .pullRequests(nil), .pullRequests("CubeSandbox"),
      .issues(nil), .issues("CubeSandbox"), .history, .reading(nil), .reading("Pingora"), .lookingThrough,
      .library, .saving, .writing, .tidying, .working,
    ]
    for var label in activities.map(\.words) + [LociWork.unspecified.words] {
      label.locale = Locale(identifier: "en")
      let english = String(localized: label)
      label.locale = Locale(identifier: "zh-Hans")
      #expect(String(localized: label) == english)
    }
  }

  @Test func beforeAnyToolLociIsThinking() {
    #expect(Self.doing() == .thinking)
    #expect(Self.doing(Self.message(.thinking("先查文档"))) == .thinking)
  }

  @Test func lookingAtARepositorysPullRequestsSaysWhichRepository() {
    let listed = Self.tool(.execute, "/bin/zsh -lc 'gh pr list -R tencentcloud/CubeSandbox --limit 20'")

    #expect(Self.doing(listed) == .pullRequests("CubeSandbox"))
    #expect(Self.doing(Self.tool(.execute, "gh pr view 42 --repo e2b-dev/infra")) == .pullRequests("infra"))
    #expect(Self.doing(Self.tool(.execute, "gh pr list")) == .pullRequests(nil))
    #expect(Self.doing(Self.tool(.execute, "gh issue list -R e2b-dev/infra")) == .issues("infra"))
  }

  @Test func aWebSearchSaysWhatIsSearchedFor() {
    #expect(Self.doing(Self.tool(.search, "firecracker jailer", name: "webSearch")) == .searching("firecracker jailer"))
  }

  @Test func readingAPageOnTheWebSaysWhichSite() {
    #expect(Self.doing(Self.tool(.other, "https://github.com/e2b-dev/infra", name: "WebFetch")) == .site("github.com"))
    #expect(Self.doing(Self.tool(.execute, "curl -sL https://www.kernel.org/doc/x.html")) == .site("kernel.org"))
  }

  @Test func readingADocumentSaysItsTitleAndNeverAPathOrExtension() {
    #expect(Self.doing(Self.tool(.read, "/w/docs/firecracker-design.md")) == .reading("firecracker design"))
    #expect(Self.doing(Self.tool(.read, "/w/src/main.rs")) == .reading(nil))
    #expect(Self.doing(Self.tool(.read, "/w/library/0193/text.md")) == .reading(nil))
  }

  @Test func theLibraryCommandSaysWhatItDoesToTheLibrary() {
    #expect(Self.doing(Self.tool(.execute, "loci search jailer")) == .library)
    #expect(Self.doing(Self.tool(.execute, "/bin/zsh -lc 'loci save https://a.example/x'")) == .saving)
    #expect(Self.doing(Self.tool(.execute, #""$LOCI" search jailer"#)) == .library)
    #expect(Self.doing(Self.tool(.execute, #"/bin/zsh -lc '"$LOCI" save https://a.example/x'"#)) == .saving)
  }

  @Test func otherWorkSaysWhatKindOfWorkItIs() {
    #expect(Self.doing(Self.tool(.edit, "/w/notes/2026-11-20.md")) == .writing)
    #expect(Self.doing(Self.tool(.create, "/w/workspace/a.md")) == .writing)
    #expect(Self.doing(Self.tool(.execute, "git log --oneline -20")) == .history)
    #expect(Self.doing(Self.tool(.search, "jailer", name: "grep")) == .lookingThrough)
    #expect(Self.doing(Self.tool(.execute, "python3 check.py")) == .working)
  }

  @Test func theLastThingDoneIsWhatLociIsDoingNow() {
    let doing = Self.doing(
      Self.tool(.search, "jailer", name: "webSearch", state: .succeeded), Self.message(.thinking("想")),
      Self.tool(.read, "/w/a/jailer-notes.md"))

    #expect(doing == .reading("jailer notes"))
  }

  @Test func aLongSearchIsCutShortAndAnAddressInItIsOnlyItsSite() {
    let search = Self.tool(.search, "'Apache-2.0' in https://github.com/e2b-dev/runtime", name: "webSearch")
    let long = Self.tool(.search, "firecracker jailer seccomp cgroup namespaces escape", name: "webSearch")

    #expect(Self.doing(search) == .searching("'Apache-2.0' in github.com"))
    #expect(Self.doing(long) == .searching("firecracker jailer seccomp…"))
  }
}
