import LociModel
import Testing

@testable import LociUI

@MainActor
struct BundledPiNavigationTests {
  @Test func choosingBundledPiBeforeItIsReadyOpensModelSettings() async throws {
    let host = FakeHost(try Sample(), modelSettings: SetupAccess())
    var opened: Place?
    await chooseRuntime(Runtime(provider: .bundledPi), on: host, openPlace: OpenPlace { opened = $0 })
    #expect(opened == .settings(.models))
  }

  @Test func choosingCodexKeepsTheReaderInTheConversation() async throws {
    let host = FakeHost(try Sample(), modelSettings: SetupAccess())
    var opened: Place?
    await chooseRuntime(Runtime(provider: .codex), on: host, openPlace: OpenPlace { opened = $0 })
    #expect(opened == nil)
  }
}

private struct SetupAccess: ModelSettingsAccess {
  func readModelSettings() async throws(HostError) -> ModelSettingsState {
    ModelSettingsState(settings: ModelSettings(), hasKey: false, cacheBytes: 0)
  }

  func saveModelSettings(_ settings: ModelSettings, key: ModelKeyChange) async throws(HostError) -> ModelSettingsState {
    try await readModelSettings()
  }

  func testModelService(_ service: ModelService, key: String?) async throws(HostError) {}
  func clearTranslationCache() async throws(HostError) {}
}
