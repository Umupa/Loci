import AppKit
import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
@Suite(.serialized, .onStage)
struct ModelSettingsSnapshots {
  @Test(arguments: Snapshot.Appearance.allCases)
  func theModelServiceAndTranslationSettingsFitInBothAppearances(appearance: Snapshot.Appearance) async throws {
    let service = try #require(
      ModelService(provider: .compatible, model: "gpt-5-mini", baseURL: URL(string: "https://models.example.test/v1")))
    let settings = ModelSettings(service: service, translation: TranslationSettings(language: "zh-Hans", smart: true))
    let state = ModelSettingsState(settings: settings, hasKey: true, cacheBytes: 2_400_000)
    try await Self.shoot("settings-models", state: state, appearance: appearance)
  }

  @Test(arguments: Snapshot.Appearance.allCases)
  func bundledPiUsesTheComponentDownloadRow(appearance: Snapshot.Appearance) async throws {
    let service = try #require(ModelService(provider: .openAI, model: "gpt-5-mini"))
    let state = ModelSettingsState(settings: ModelSettings(service: service), hasKey: true, cacheBytes: 0)
    let work: Transfer =
      appearance == .light ? .running(Fraction(0.37)) : .failed("The Pi download did not match its checksum.")
    try await Self.shoot("settings-bundled-pi", state: state, piWork: work, appearance: appearance)
  }

  private static func shoot(
    _ name: String, state: ModelSettingsState, piWork: Transfer? = nil, appearance: Snapshot.Appearance
  ) async throws {
    let model = try #require(state.settings.service?.model)
    let host = FakeHost(try Sample(), modelSettings: SampleModelSettings(state: state), piWork: piWork)
    let view = ModelSettingsPage().lociHost(host).tint(Palette.accent)
    let quiet = Quiet(host.activity)
    let file = try await Snapshot.render(
      view, named: name, size: CGSize(width: 800, height: piWork == nil ? 820 : 860), appearance: appearance,
      locale: Locale(identifier: appearance == .dark ? "en" : "zh-Hans"),
      until: { window in
        guard quiet.settled(), let content = window.contentView else { return false }
        content.layoutSubtreeIfNeeded()
        return hasModelField(model, in: content)
      }, steady: true)
    #expect(try Data(contentsOf: file).count > 10_000)
  }

  private static func hasModelField(_ model: String, in view: NSView) -> Bool {
    if let field = view as? NSTextField, field.isEnabled, field.stringValue == model { return true }
    return view.subviews.contains { hasModelField(model, in: $0) }
  }
}

private struct SampleModelSettings: ModelSettingsAccess {
  let state: ModelSettingsState

  func readModelSettings() async throws(HostError) -> ModelSettingsState { state }
  func saveModelSettings(_ settings: ModelSettings, key: ModelKeyChange) async throws(HostError) -> ModelSettingsState {
    state
  }
  func testModelService(_ service: ModelService, key: String?) async throws(HostError) {}
  func clearTranslationCache() async throws(HostError) {}
}
