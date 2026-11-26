import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// TD-S1, TD-S2, TD-S4: the tidy button beside the translate button, ready, running, failed and waiting for a
/// translation, in light and dark; and over the article.
@MainActor
@Suite(.serialized, .onStage)
struct TidySnapshots {
  static func corner(_ tidy: TidyProgress?, translating: Bool = false) -> some View {
    HStack(spacing: Spacing.xs) {
      TidyButton(progress: tidy, translating: translating) {}
      TranslateButton(
        language: ArticleLanguage(
          translation: nil, progress: translating ? .running(Fraction(0.3)) : nil),
        mode: .constant(.both)
      ) {}
      .disabled(tidy.map { if case .running = $0 { true } else { false } } ?? false)
    }
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func states(appearance: Snapshot.Appearance) async throws {
    let view = VStack(alignment: .trailing, spacing: Spacing.m) {
      Self.corner(nil)
      Self.corner(.running(Fraction(0.45)))
      Self.corner(.failed("the model ran out of time"))
      Self.corner(nil, translating: true)
    }
    .padding(Spacing.m)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .lociHost(FakeHost(try Sample(problems: false)))
    try await Snapshot.render(view, named: "tidy-button", size: CGSize(width: 220, height: 220), appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func overTheArticle(appearance: Snapshot.Appearance) async throws {
    try await ScreenSnapshots.shoot(
      "article-tidy", try TranslationSnapshots.window(nil, translated: false), appearance: appearance,
      size: ScreenSnapshots.wide)
  }

  @Test func theButtonSaysWhereTidyingStands() {
    #expect(TidyFace(progress: nil, translating: false, justTidied: false) == .ready)
    #expect(
      TidyFace(progress: .running(Fraction(0.5)), translating: false, justTidied: false) == .running(Fraction(0.5)))
    #expect(TidyFace(progress: nil, translating: false, justTidied: true) == .tidied)
    #expect(TidyFace(progress: .failed("no"), translating: false, justTidied: false) == .failed("no"))
    #expect(TidyFace(progress: nil, translating: true, justTidied: false) == .waiting)
    #expect(TidyFace.ready.clickable && TidyFace.failed("no").clickable)
    #expect(!TidyFace.running(Fraction(0)).clickable && !TidyFace.waiting.clickable && !TidyFace.tidied.clickable)
  }
}
