import AppKit
import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// UI-S8: what the runtime island does as you pick in it, and where it sits.
@MainActor
struct RuntimeIslandTests {
  @Test func pickingAModelWhoseAgentThinksMovesOnToThinking() {
    let picked = Runtime(provider: .codex, model: "gpt-6.1-sol")
    #expect(RuntimeIslandStep.after(picking: picked, on: .model) == .show(.effort))
  }

  @Test func pickingAModelWhoseAgentCannotThinkCloses() {
    let picked = Runtime(provider: .grok, model: "grok-5")
    #expect(RuntimeIslandStep.after(picking: picked, on: .model) == .close)
  }

  @Test func pickingAThinkingEffortCloses() {
    let picked = Runtime(provider: .codex, model: "gpt-6.1-sol", effort: .high)
    #expect(RuntimeIslandStep.after(picking: picked, on: .effort) == .close)
  }

  @Test func thinkingFallsBackToModelsForAnAgentWithoutEfforts() {
    #expect(RuntimeIslandTab.effort.shown(for: Runtime(provider: .grok)) == .model)
    #expect(RuntimeIslandTab.effort.shown(for: Runtime(provider: .codex)) == .effort)
  }

  @Test func inANarrowPaneTheIslandSpansTheComposer() {
    let composer = CGRect(x: 14, y: 480, width: 356, height: 48)
    let layout = RuntimeIslandLayout(composer: composer, height: 560)
    #expect(layout.minX == 14)
    #expect(layout.width == 356)
  }

  @Test func inAWideConversationTheIslandHangsFromTheComposersRightEdge() {
    let composer = CGRect(x: 14, y: 700, width: 900, height: 48)
    let layout = RuntimeIslandLayout(composer: composer, height: 760)
    #expect(layout.width == RuntimeIslandLayout.preferredWidth)
    #expect(layout.minX + layout.width == composer.maxX)
  }

  @Test func aTallerComposerPushesTheIslandUp() {
    let short = RuntimeIslandLayout(composer: CGRect(x: 14, y: 498, width: 356, height: 48), height: 560)
    let tall = RuntimeIslandLayout(composer: CGRect(x: 14, y: 451, width: 356, height: 95), height: 560)
    #expect(tall.bottomInset - short.bottomInset == 47)
    #expect(tall.bottomInset == 560 - 451 + RuntimeIslandLayout.gap)
  }

  @Test func theIslandGrowsFromAboveItsTrigger() {
    let layout = RuntimeIslandLayout(composer: CGRect(x: 0, y: 500, width: 400, height: 48), height: 560)
    let trigger = CGRect(x: 0 + 400 - 166, y: 508, width: 32, height: 32)
    let anchor = layout.growthAnchor(trigger: trigger)
    #expect(anchor.y == 1)
    #expect(abs(anchor.x * layout.width + layout.minX - trigger.midX) < 0.001)
  }

  @Test func aFavoriteModelStaysAfterReopening() throws {
    let suiteName = "loci.tests.favorites.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let store = ModelFavorites(defaults: defaults)
    store.toggle(provider: .codex, model: "gpt-6.1-sol", name: "GPT-6.1-Sol")
    #expect(store.contains(provider: .codex, model: "gpt-6.1-sol"))

    let reloaded = ModelFavorites(defaults: defaults)
    #expect(reloaded.items == [FavoriteModel(provider: .codex, id: "gpt-6.1-sol", name: "GPT-6.1-Sol")])
  }

  @Test func starringAFavoriteAgainUnstarsIt() throws {
    let suiteName = "loci.tests.favorites.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    let store = ModelFavorites(defaults: defaults)
    store.toggle(provider: .claudeCode, model: "opus", name: "Opus")
    store.toggle(provider: .claudeCode, model: "opus", name: "Opus")
    #expect(!store.contains(provider: .claudeCode, model: "opus"))
    #expect(store.items.isEmpty)
  }

  @Test func bundledPiHasItsOwnMarkInBothAppearances() throws {
    for scheme in [ColorScheme.light, ColorScheme.dark] {
      let bundled = try #require(MarkArt.agent(.bundledPi, in: scheme)?.tiffRepresentation)
      let pi = try #require(MarkArt.agent(.pi, in: scheme)?.tiffRepresentation)
      #expect(bundled != pi)
    }
  }

  @Test func aCapabilityInParenthesesIsShownApartFromTheModelsName() {
    let tagged = Agents.splitModelTag("Claude Sonnet 4.6 (Thinking)")
    #expect(tagged.title == "Claude Sonnet 4.6")
    #expect(tagged.tag == "Thinking")

    let plain = Agents.splitModelTag("Gemini 4 Hydrogen")
    #expect(plain.title == "Gemini 4 Hydrogen")
    #expect(plain.tag == nil)
  }

  @Test func theBackgroundModelIsNamedWithoutItsProvider() {
    #expect(Agents.modelName("deepseek-hk/DeepSeek-V4.1-Flash-1017") == "DeepSeek-V4.1-Flash-1017")
    #expect(Agents.modelName("opus") == "Opus")
  }

  @Test func onlyExtraHighAndMaxRipple() {
    #expect(EffortTileShimmer.color(for: .xhigh) != nil)
    #expect(EffortTileShimmer.color(for: .max) != nil)
    #expect(EffortTileShimmer.color(for: .high) == nil)
    #expect(EffortTileShimmer.color(for: .low) == nil)
    #expect(EffortTileShimmer.color(for: nil) == nil)
  }
}
