import LociModel
import Testing

@testable import LociUI

@MainActor
struct BundledPiNavigationTests {
  @Test func choosingBundledPiBeforeAnyModelIsOfferedOpensModelServices() async throws {
    let host = FakeHost(try Sample(), modelSettings: SampleModelAccess(SampleModelAccess.empty))
    var opened: Place?
    await chooseRuntime(
      Runtime(provider: .bundledPi), for: .conversation(.main), on: host, changesAllowed: true,
      openPlace: OpenPlace { opened = $0 })
    #expect(opened == .settings(.models))
  }

  @Test func choosingBundledPiWithAModelButNoPiYetOpensTheCompanionsSettings() async throws {
    let host = FakeHost(try Sample(), modelSettings: SampleModelAccess())
    var opened: Place?
    await chooseRuntime(
      Runtime(provider: .bundledPi), for: .conversation(.main), on: host, changesAllowed: true,
      openPlace: OpenPlace { opened = $0 })
    #expect(opened == .settings(.agents))
  }

  @Test func choosingCodexKeepsTheReaderInTheConversation() async throws {
    let host = FakeHost(try Sample(), modelSettings: SampleModelAccess())
    var opened: Place?
    await chooseRuntime(
      Runtime(provider: .codex), for: .conversation(.main), on: host, changesAllowed: true,
      openPlace: OpenPlace { opened = $0 })
    #expect(opened == nil)
  }

  /// R-S7: with the Mac behind the window offline, picking a runtime sends nothing and opens nothing.
  @Test func choosingWhileOfflineChangesNothing() async throws {
    let host = FakeHost(try Sample(), modelSettings: SampleModelAccess(SampleModelAccess.empty))
    var opened: Place?
    await chooseRuntime(
      Runtime(provider: .bundledPi), for: .conversation(.main), on: host, changesAllowed: false,
      openPlace: OpenPlace { opened = $0 })
    #expect(opened == nil)
  }
}
