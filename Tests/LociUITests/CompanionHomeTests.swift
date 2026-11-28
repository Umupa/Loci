import LociModel
import Testing

@testable import LociUI

/// CH-S4, CH-S5: the dot beside the companion's face, and the tabs of its page.
struct CompanionHomeTests {
  @Test func theDotIsGreenWhileTheCompanionIsAwakeOrALittleTired() {
    #expect(PresenceTone(tiredness: .awake, offline: false) == .awake)
    #expect(PresenceTone(tiredness: .tired, offline: false) == .awake)
    #expect(PresenceTone(tiredness: nil, offline: false) == .awake)
  }

  @Test func theDotIsGrayWhileTheCompanionIsSleepyAsleepOrItsMacOffline() {
    #expect(PresenceTone(tiredness: .sleepy, offline: false) == .away)
    #expect(PresenceTone(tiredness: .asleep, offline: false) == .away)
    #expect(PresenceTone(tiredness: .awake, offline: true) == .away)
  }

  @Test func thePageHasTheCompanionsOwnTabsThenItsSettings() {
    #expect(LociTab.groups == [[.soul, .memory, .watch, .diary], [.models, .timers, .connectors, .usage]])
    #expect(Set(LociTab.groups.joined()) == Set(LociTab.allCases))
  }

  @Test func thePageOpensAtTheTabLastLookedAtUnlessItWasOpenedAtOne() {
    #expect(LociTab.opening(asked: nil, remembered: LociTab.diary.rawValue) == .diary)
    #expect(LociTab.opening(asked: .connectors, remembered: LociTab.diary.rawValue) == .connectors)
    #expect(LociTab.opening(asked: nil, remembered: "") == .soul)
    #expect(LociTab.opening(asked: nil, remembered: "gone") == .soul)
  }

  /// CH-S1: the sidebar shows the last bubble the companion sent, as plain words on one line.
  @Test func theSidebarLineIsTheLastBubbleAsOnePlainLine() {
    #expect(CompanionNow.oneLine("Borg 读完了。\n\n写好了，放在**调度器**里。\n最值得看抢占。") == "写好了，放在调度器里。 最值得看抢占。")
    #expect(CompanionNow.oneLine("") == nil)
  }
}
