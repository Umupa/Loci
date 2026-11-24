import LociModel
import Testing

@testable import LociUI

/// M-S7, M-S9: the page saves every change as it is made and a key on its own.
@MainActor
struct ModelServicesModelTests {
  @Test func everyChangeIsSavedWithoutASaveButtonAndShowsAtOnce() async throws {
    let access = SampleModelAccess()
    let model = ModelServicesModel(access: access)
    await model.load()
    let kimi = model.add(.kimi)
    model.change(kimi) { $0.models = [ProviderModel(id: "kimi-k3", checked: true)] }
    #expect(model.settings.providers.last?.checkedModels == ["kimi-k3"])
    await model.setKey("  sk-kimi  ", for: kimi)
    #expect(access.saves.last?.providers.last?.models == [ProviderModel(id: "kimi-k3", checked: true)])
    #expect(access.keys.last?.0 == "sk-kimi")
    #expect(model.hasKey(kimi))
    #expect(model.groups.map(\.provider).contains(kimi))
  }

  @Test func aProviderTurnedOffOffersNothingToTheMenus() async throws {
    let model = ModelServicesModel(access: SampleModelAccess())
    await model.load()
    model.change(ModelProviderID(.openRouter)) { $0.enabled = false }
    #expect(model.groups.map(\.provider) == [ModelProviderID(.deepSeek)])
  }

  @Test func tryingSaysHowLongItTook() async throws {
    let model = ModelServicesModel(access: SampleModelAccess())
    await model.load()
    await model.test(ModelProviderID(.deepSeek), model: "deepseek-chat")
    #expect(model.latestTrial(of: ModelProviderID(.deepSeek)) == .took(.milliseconds(312)))
  }
}
