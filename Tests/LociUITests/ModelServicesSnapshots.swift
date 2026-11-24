import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

/// M-S7–M-S11: the model services page with a provider open, the ones that are off unfolded, and the providers
/// to add; in light and dark.
@MainActor
@Suite(.serialized, .onStage)
struct ModelServicesSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func aProviderOpenInPlace(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "settings-models", ModelServicesPage(open: ModelProviderID(.deepSeek)), appearance: appearance,
      waitingFor: "https://api.deepseek.com")
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func theProvidersThatAreOffUnfolded(appearance: Snapshot.Appearance) async throws {
    try await Self.shoot(
      "settings-models-off", ModelServicesPage(offUnfolded: true), appearance: appearance, waitingFor: nil)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func theProvidersToAdd(appearance: Snapshot.Appearance) async throws {
    let added: Set<ModelPreset> = [.deepSeek, .openRouter, .anthropic, .openAI]
    let file = try await Snapshot.render(
      AddProviderSheet(added: added) { _ in }, named: "settings-models-add", size: CGSize(width: 520, height: 420),
      appearance: appearance, locale: Self.locale(appearance))
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  private static func shoot(
    _ name: String, _ page: ModelServicesPage, appearance: Snapshot.Appearance, waitingFor address: String?
  ) async throws {
    let host = FakeHost(try Sample(), modelSettings: SampleModelAccess())
    let file = try await Snapshot.render(
      page.lociHost(host).tint(Palette.accent), named: name, size: CGSize(width: 760, height: 980),
      appearance: appearance, locale: locale(appearance),
      until: { window in
        guard let content = window.contentView else { return false }
        content.layoutSubtreeIfNeeded()
        return hasField(address ?? "", in: content)
      }, steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  private static func locale(_ appearance: Snapshot.Appearance) -> Locale {
    Locale(identifier: appearance == .dark ? "en" : "zh-Hans")
  }

  /// A field holding `text`, or, when `text` is empty, the prompt editors under the providers.
  private static func hasField(_ text: String, in view: NSView) -> Bool {
    if text.isEmpty, view is NSTextView { return true }
    if let field = view as? NSTextField, field.stringValue == text { return true }
    return view.subviews.contains { hasField(text, in: $0) }
  }
}
