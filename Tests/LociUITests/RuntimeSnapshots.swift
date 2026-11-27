import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// UI-S8, UI-S27: what the companion runs on, in the 模型 tab and beside the send button.
@MainActor
@Suite(.serialized, .onStage)
struct RuntimeSnapshots {
  private static func sample() throws -> Sample {
    var sample = try Sample(problems: false)
    sample.ownRuntimes = [
      .init(
        conversation: .item(sample.borg.id), title: sample.borg.title,
        runtime: Runtime(provider: .antigravity, model: "gemini-4-hydrogen", effort: .high)),
      .init(conversation: .project(EntityID()), title: "Loci", runtime: Runtime(provider: .grok, model: "grok-5")),
    ]
    return sample
  }

  /// UI-S27: a row per kind, the conversations that chose otherwise hanging under it, and Background last.
  @Test(arguments: Snapshot.Appearance.allCases)
  func modelsTab(appearance: Snapshot.Appearance) async throws {
    let view = HStack(spacing: 0) { LociScreen(tab: .models) }
      .lociHost(FakeHost(try Self.sample(), library: try SampleLibrary()))
    try await ScreenSnapshots.shoot("loci-models", view, appearance: appearance, size: CGSize(width: 1036, height: 820))
    try await ScreenSnapshots.shoot(
      "loci-models-en", view, appearance: appearance, english: true, size: CGSize(width: 1036, height: 820))
  }

  /// UI-S8: the island's model half with favorites and the way back to the default, beside both triggers.
  @Test(arguments: Snapshot.Appearance.allCases)
  func islandModels(appearance: Snapshot.Appearance) async throws {
    let sample = try Self.sample()
    let own = Runtime(provider: .codex, model: "gpt-6.1-sol", effort: .high)
    let use = RuntimeInUse(
      runtime: own, kindDefault: Runtime(provider: .claudeCode, model: "opus", effort: .medium), isOwn: true)
    let suiteName = "loci.snapshots.favorites.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
    let favorites = ModelFavorites(defaults: defaults)
    favorites.toggle(provider: .codex, model: "gpt-6.1-sol", name: "GPT-6.1-Sol")

    let view = VStack(alignment: .trailing, spacing: 18) {
      Self.card(
        RuntimeIslandCard(
          conversation: .item(sample.borg.id), use: use, installations: FakeHost.installations, favorites: favorites,
          close: {}, choose: { _ in }))
      HStack(spacing: 16) {
        RuntimeCapsule(conversation: .item(sample.borg.id), compact: true, islandOpen: .constant(false))
        HStack(spacing: 0) {
          RuntimeCapsule(conversation: .item(sample.borg.id), islandOpen: .constant(false))
          AttachButton {}
        }
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .environment(\.standIns, StandIns())
    .lociHost(FakeHost(sample))
    try await ScreenSnapshots.shoot(
      "runtime-island", view, appearance: appearance, size: CGSize(width: 420, height: 470))
  }

  /// UI-S8: the island's thinking half, rippling on Extra High and on Max.
  @Test(arguments: Snapshot.Appearance.allCases)
  func islandThinking(appearance: Snapshot.Appearance) async throws {
    let sample = try Self.sample()
    let view = HStack(alignment: .top, spacing: 24) {
      ForEach([ThinkingEffort.xhigh, .max], id: \.self) { effort in
        let runtime = Runtime(provider: .codex, model: "gpt-6.1-sol", effort: effort)
        Self.card(
          RuntimeIslandCard(
            conversation: .item(sample.borg.id),
            use: RuntimeInUse(runtime: runtime, kindDefault: runtime, isOwn: false),
            installations: FakeHost.installations, initialTab: .effort, close: {}, choose: { _ in }))
      }
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .environment(\.standIns, StandIns())
    .lociHost(FakeHost(sample))
    try await ScreenSnapshots.shoot(
      "runtime-effort", view, appearance: appearance, size: CGSize(width: 776, height: 320))
  }

  /// UI-S8: the island open over a conversation beside the text, as wide as the composer under it.
  @Test(arguments: Snapshot.Appearance.allCases)
  func islandBesideTheText(appearance: Snapshot.Appearance) async throws {
    try await Self.shootIsland("companion-island", scale: .companion, appearance: appearance, width: 384)
  }

  /// UI-S8: the island open over the main conversation, hanging from the composer's right edge.
  @Test(arguments: Snapshot.Appearance.allCases)
  func islandInTheMainConversation(appearance: Snapshot.Appearance) async throws {
    try await Self.shootIsland("main-island", scale: .main, appearance: appearance, width: 760)
  }

  private static func shootIsland(
    _ name: String, scale: TalkScale, appearance: Snapshot.Appearance, width: CGFloat
  ) async throws {
    let sample = try Self.sample()
    let view = ConversationView(
      conversation: try sample.conversation(), draft: .constant(nil), revealPassage: { _ in },
      send: { (_: String, _: Passage?) async throws(HostError) -> Done in Done() }, stop: {}, scale: scale
    )
    .environment(\.standIns, StandIns(runtimeIsland: .model))
    .lociHost(FakeHost(sample))
    try await ScreenSnapshots.shoot(name, view, appearance: appearance, size: CGSize(width: width, height: 560))
  }

  private static func card(_ content: some View) -> some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    return
      content
      .background(shape.fill(Palette.menuFace))
      .overlay(shape.strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      .cardShadow(shape)
  }
}
