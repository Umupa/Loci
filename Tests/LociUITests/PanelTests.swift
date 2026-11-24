import Foundation
import LociModel
import Testing

@testable import LociUI

@MainActor
struct PanelTests {
  @Test func aSentenceIsBoldOnlyBetweenDoubleStars() {
    #expect(
      BoldSpans("**v0.8.0** 正式版发布，**你的 PR #2214** 在里面。").spans == [
        .init(text: "v0.8.0", bold: true), .init(text: " 正式版发布，", bold: false),
        .init(text: "你的 PR #2214", bold: true), .init(text: " 在里面。", bold: false),
      ])
    #expect(BoldSpans("没有重点").spans == [.init(text: "没有重点", bold: false)])
    #expect(BoldSpans("**没合上").spans == [.init(text: "**没合上", bold: false)])
  }

  @Test func aSiteIsKnownByItsDomainWhateverTheSubdomain() {
    #expect(SiteMark("github.com") == .github)
    #expect(SiteMark("gist.github.com") == .github)
    #expect(SiteMark("https://github.com/tencentcloud/CubeSandbox") == .github)
    #expect(SiteMark("news.ycombinator.com") == .hackerNews)
    #expect(SiteMark("x.com") == .x)
    #expect(SiteMark("twitter.com") == .x)
    #expect(SiteMark("www.notion.so") == .notion)
  }

  @Test func anyOtherSiteIsTheFirstLetterOfItsName() {
    #expect(SiteMark("www.simonwillison.net") == .letter("S"))
    #expect(SiteMark("blog.primeradiant.com") == .letter("P"))
    #expect(SiteMark("") == .letter("·"))
  }

  @Test func aPanelLociKeepsCanBeRefreshedRevisedMovedAndRemoved() {
    let panel = SamplePanels.feed
    #expect(PanelMenu.entries(for: .panel(panel)) == [.refresh, .revise, .moveToTop, .remove])
  }

  @Test func readingNowCanOnlyBeMovedToTheTop() throws {
    #expect(PanelMenu.entries(for: .reading(try SamplePanels.readingNow())) == [.moveToTop])
  }

  @Test func revisingAPanelFillsTheComposerWithItsTitle() {
    let fill = ComposerFill.revising(SamplePanels.feed, serial: 1, locale: Locale(identifier: "zh-Hans"))
    #expect(fill.text == "改一下『关注精选』：")
    let english = ComposerFill.revising(SamplePanels.feed, serial: 1, locale: Locale(identifier: "en"))
    #expect(english.text == "Change “关注精选”: ")
  }

  @Test func aNewPanelRequestSaysItIsOne() {
    #expect(
      NewPanel.request("盯着 CubeSandbox 的新版本", locale: Locale(identifier: "zh-Hans")) == "创建一个新面板：盯着 CubeSandbox 的新版本")
    #expect(
      NewPanel.request("Follow the releases", locale: Locale(identifier: "en"))
        == "Create a new panel: Follow the releases")
  }

  @Test func theSkeletonStaysUntilANewPanelAppears() {
    let building = NewPanel.building(known: ["radar"], started: false, sources: .loci)
    #expect(building.settled(names: ["radar"], working: false) == building)
    #expect(
      building.settled(names: ["radar"], working: true) == .building(known: ["radar"], started: true, sources: .loci))
    #expect(building.settled(names: ["radar", "reads"], working: true) == nil)
  }

  @Test func theSkeletonGoesWhenTheTurnEndsWithoutAPanel() {
    let started = NewPanel.building(known: ["radar"], started: true, sources: .loci)
    #expect(started.settled(names: ["radar"], working: false) == nil)
  }

  @Test func askingForANewPanelIsNotSettledByTheColumn() {
    #expect(NewPanel.asking.settled(names: ["radar", "reads"], working: true) == .asking)
  }

  @Test func readingNowSaysHowLongTheLatestHasLeft() throws {
    let zh = Locale(identifier: "zh-Hans")
    let readings = try SamplePanels.readingNow()
    #expect(ReadingPanel.summary(readings, locale: zh) == "**《Firecracker 逃逸链复盘》**还剩 12 分钟。")
    let unknown = [ReadingNow(item: readings[0].item, progress: 0.64)]
    #expect(ReadingPanel.summary(unknown, locale: zh) == "**《Firecracker 逃逸链复盘》**读到 64%。")
    #expect(
      ReadingPanel.summary(readings, locale: Locale(identifier: "en"))
        == "**Firecracker 逃逸链复盘**: 12 min left.")
  }

  @Test func turningAPageForwardSlidesInFromTheRight() {
    #expect(PageTurn(from: 0, to: 1) == .forward)
    #expect(PageTurn(from: 1, to: 0) == .back)
  }

  @Test func aLongPanelKeepsItsLastFittingRowClearAndPreviewsWhatFollows() throws {
    let preview = try #require(PanelPreview(height: 421, rowEnds: [52, 117, 199, 278, 353, 411]))
    #expect(preview.showsRow(endingAt: 278))
    #expect(!preview.showsRow(endingAt: 353))
    #expect(preview.height == 302)
  }

  @Test func aShortPanelOrOneWithOnlyTrailingSpaceHasNoPreview() {
    #expect(PanelPreview(height: 330, rowEnds: [52, 240, 322]) == nil)
    #expect(PanelPreview(height: 352, rowEnds: [52, 296]) == nil)
  }

  @Test func aTallFirstRowStaysWholeAndOnlyFollowingContentCanBePreviewed() throws {
    #expect(PanelPreview(height: 399, rowEnds: [399]) == nil)
    let preview = try #require(PanelPreview(height: 412, rowEnds: [399, 412]))
    #expect(preview.showsRow(endingAt: 399))
    #expect(!preview.showsRow(endingAt: 412))
    #expect(preview.height == 412)
  }

  @Test func aRequestIsMarkedWithTheSitesItNames() {
    let zh = Locale(identifier: "zh-Hans")
    #expect(PanelSources.named(in: "盯着 https://github.com/openai/codex 的发布", locale: zh).sites == ["github.com"])
    #expect(
      PanelSources.named(in: "每天看 Hacker News 首页和 notion.so 里的岗位", locale: zh).sites == [
        "news.ycombinator.com", "notion.so",
      ])
    #expect(PanelSources.named(in: "我关注的人在 X 上说了什么", locale: zh).sites == ["x.com"])
    #expect(PanelSources.named(in: "simonwillison.net 的新文章", locale: zh) == PanelSources(sites: ["simonwillison.net"]))
  }

  @Test func aRequestNamingNoSiteIsMarkedWithLoci() {
    #expect(PanelSources.named(in: "每周帮我挑点好读的", locale: Locale(identifier: "zh-Hans")) == .loci)
  }

  @Test func anExampleSentAsItIsKeepsItsMarks() {
    let zh = Locale(identifier: "zh-Hans")
    #expect(
      PanelSources.named(in: "每周挑三篇沙箱相关的好文章", locale: zh) == PanelSources(sites: ["news.ycombinator.com"], loci: true))
    #expect(
      PanelSources.named(in: "Pick three good reads on sandboxes each week", locale: Locale(identifier: "en"))
        == PanelSources(sites: ["news.ycombinator.com"], loci: true))
  }

  @Test func onlyTheReadingExampleReadsTheLibraryToo() {
    #expect(PanelExample.all.map(\.sources.loci) == [false, true, false, false])
  }

  @Test func aRequestThatAlsoReadsTheLibraryIsMarkedWithLociAfterItsSites() {
    let zh = Locale(identifier: "zh-Hans")
    let both = PanelSources(sites: ["news.ycombinator.com"], loci: true)
    #expect(PanelSources.named(in: "每周从 Hacker News 挑三篇和我资料库有关的文章", locale: zh) == both)
    #expect(PanelSources.named(in: "看 Hacker News 上和我读过的东西相关的讨论", locale: zh) == both)
    #expect(
      PanelSources.named(
        in: "Pick from https://news.ycombinator.com what relates to loci://library/01KAB",
        locale: Locale(identifier: "en"))
        == both)
    #expect(PanelSources.named(in: "Hacker News threads about my library", locale: Locale(identifier: "en")) == both)
  }
}
