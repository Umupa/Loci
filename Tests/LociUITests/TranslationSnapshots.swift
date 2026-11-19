import Foundation
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// The Borg article with its translation beside each passage and in place of it, in light and dark.
@MainActor
@Suite(.serialized)
struct TranslationSnapshots {
  static func window(_ mode: SubtitleMode?, translated: Bool = true) throws -> some View {
    var sample = try Sample(problems: false)
    sample.translation = try Sample.borgInChinese()
    if !translated { sample.translation = try ArticleTranslation(language: "zh-Hans", passages: []) }
    let defaults = UserDefaults(suiteName: "loci-translation-snapshots") ?? .standard
    defaults.set((mode ?? .both).rawValue, forKey: SubtitleMode.key)
    let window = WindowState(place: .library(nil), pages: [.item(sample.borg.id)])
    return ScreenSnapshots.root(sample, at: window).defaultAppStorage(defaults)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func sideBySide(appearance: Snapshot.Appearance) async throws {
    try await ScreenSnapshots.shoot(
      "article-both", try Self.window(.both), appearance: appearance, size: ScreenSnapshots.wide)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func translationAlone(appearance: Snapshot.Appearance) async throws {
    try await ScreenSnapshots.shoot(
      "article-translation", try Self.window(.translation), appearance: appearance, size: ScreenSnapshots.wide)
  }
}
