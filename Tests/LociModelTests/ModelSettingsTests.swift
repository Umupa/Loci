import Foundation
import LociModel
import Testing

struct ModelSettingsTests {
  @Test func eachPresetCarriesItsOfficialAddressAndProtocol() {
    let addresses = ModelPreset.allCases.map { ($0, $0.address?.url.absoluteString) }
    #expect(
      addresses.map(\.1) == [
        "https://api.openai.com/v1", "https://api.anthropic.com", "https://openrouter.ai/api/v1",
        "https://api.deepseek.com", "https://api.moonshot.cn/v1", "https://open.bigmodel.cn/api/paas/v4",
        "https://dashscope.aliyuncs.com/compatible-mode/v1", "https://api.siliconflow.cn/v1",
        "https://ark.cn-beijing.volces.com/api/v3", "https://api.minimax.cn/v1", nil,
      ])
    #expect(ModelPreset.allCases.filter { $0.api == .anthropic } == [.anthropic])
  }

  @Test func requestsGoWhereEachProtocolExpectsThem() throws {
    let deepSeek = try #require(settings(.deepSeek, models: ["deepseek-chat"]).service(for: choice(.deepSeek)))
    #expect(deepSeek.endpoint.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(deepSeek.models.absoluteString == "https://api.deepseek.com/models")
    let anthropic = try #require(settings(.anthropic, models: ["claude"]).service(for: choice(.anthropic, "claude")))
    #expect(anthropic.endpoint.absoluteString == "https://api.anthropic.com/v1/messages")
    #expect(anthropic.models.absoluteString == "https://api.anthropic.com/v1/models")
    let versioned = try #require(ModelAddress("https://api.minimax.cn/anthropic/v1/"))
    #expect(
      ModelAPI.anthropic.route("messages", at: versioned).absoluteString
        == "https://api.minimax.cn/anthropic/v1/messages")
  }

  @Test func anAddressWithCredentialsQueryOrPlainHttpOffLoopbackIsRefused() {
    #expect(ModelAddress("https://example.test/v1") != nil)
    #expect(ModelAddress("  http://localhost:11434/v1 ") != nil)
    #expect(ModelAddress("http://example.test/v1") == nil)
    #expect(ModelAddress("https://user:pass@example.test/v1") == nil)
    #expect(ModelAddress("https://example.test/v1?key=1") == nil)
    #expect(ModelAddress("https://example.test/v1#models") == nil)
    #expect(ModelAddress("example.test") == nil)
  }

  @Test func menusListOnlyCheckedModelsOfProvidersThatAreOn() {
    var models = settings(.deepSeek, models: ["deepseek-chat"])
    models.providers[0].models.append(ProviderModel(id: "deepseek-reasoner", checked: false))
    var off = ModelProvider(.openAI)
    off.models = [ProviderModel(id: "gpt", checked: true)]
    off.enabled = false
    models.providers.append(off)
    #expect(models.groups.map(\.provider) == [ModelProviderID(.deepSeek)])
    #expect(models.groups.first?.models == ["deepseek-chat"])
  }

  @Test func aChoiceOnAProviderTurnedOffDeletedOrUncheckedIsNotConfigured() {
    var models = settings(.deepSeek, models: ["deepseek-chat"])
    #expect(models.service(for: choice(.deepSeek)) != nil)
    #expect(models.service(for: choice(.deepSeek, "other")) == nil)
    models.providers[0].models[0].checked = false
    #expect(models.service(for: choice(.deepSeek)) == nil)
    models.providers[0].models[0].checked = true
    models.providers[0].enabled = false
    #expect(models.service(for: choice(.deepSeek)) == nil)
    models.providers = []
    #expect(models.service(for: choice(.deepSeek)) == nil)
  }

  @Test func aChoiceThatNoLongerResolvesFallsBackToTheToolModel() {
    var models = settings(.deepSeek, models: ["deepseek-chat"])
    #expect(models.service(preferring: nil, for: .tool) == nil)
    models.toolModel = choice(.deepSeek)
    #expect(models.service(preferring: choice(.openAI, "gone"), for: .tool)?.model == "deepseek-chat")
  }

  @Test func translationFollowsTheToolModelUntilChosenApart() {
    var models = settings(.deepSeek, models: ["deepseek-chat", "deepseek-reasoner"])
    models.toolModel = choice(.deepSeek)
    #expect(models.service(preferring: nil, for: .translation)?.model == "deepseek-chat")
    models.translation.model = choice(.deepSeek, "deepseek-reasoner")
    #expect(models.service(preferring: nil, for: .translation)?.model == "deepseek-reasoner")
    #expect(models.service(preferring: nil, for: .tool)?.model == "deepseek-chat")
  }

  @Test func theToolModelLeftEmptyTakesTheFirstModelOnceThereIsOne() {
    var models = settings(.deepSeek, models: [])
    models.fillToolModel()
    #expect(models.toolModel == nil)
    models.providers[0].models = [ProviderModel(id: "deepseek-chat", checked: true)]
    models.fillToolModel()
    #expect(models.toolModel == choice(.deepSeek))
    #expect(models.translation.model == nil)
    models.toolModel = choice(.openAI, "chosen-before")
    models.fillToolModel()
    #expect(models.toolModel == choice(.openAI, "chosen-before"))
  }

  @Test func chaptersAndKeyPointsFromBefore185BecomeTheToolModelAndADifferentTranslationStaysApart() throws {
    let apart = Data(
      #"{"providers":[],"uses":{"translation":{"provider":"kimi","model":"k3"},"transcripts":{"provider":"deepSeek","model":"chat"}},"translation":{"smart":false,"transcriptPrompt":"t","articlePrompt":"a"}}"#
        .utf8)
    let decoded = try JSONDecoder().decode(ModelSettings.self, from: apart)
    #expect(decoded.toolModel == choice(.deepSeek, "chat"))
    #expect(decoded.translation.model == choice(.kimi, "k3"))

    let same = Data(
      #"{"providers":[],"uses":{"translation":{"provider":"kimi","model":"k3"},"transcripts":{"provider":"kimi","model":"k3"}},"translation":{"smart":false,"transcriptPrompt":"t","articlePrompt":"a"}}"#
        .utf8)
    let followed = try JSONDecoder().decode(ModelSettings.self, from: same)
    #expect(followed.toolModel == choice(.kimi, "k3"))
    #expect(followed.translation.model == nil)
  }

  @Test func optionsFromAMacOn185OrBeforeReadItsUses() throws {
    let old = Data(
      #"{"groups":[],"uses":{"translation":{"provider":"kimi","model":"k3"},"transcripts":{"provider":"deepSeek","model":"chat"}}}"#
        .utf8)
    let options = try JSONDecoder().decode(ModelOptions.self, from: old)
    #expect(options.toolModel == choice(.deepSeek, "chat"))
    #expect(options.translationModel == choice(.kimi, "k3"))
  }

  @Test func aCustomProviderWithoutAnAddressOffersNothing() {
    var custom = ModelProvider(custom: EntityID(), api: .openAI)
    custom.models = [ProviderModel(id: "local", checked: true)]
    let models = ModelSettings(providers: [custom])
    #expect(models.groups.isEmpty)
    #expect(custom.keyAccount.hasPrefix("provider:custom-"))
  }

  @Test func aCompanionModelRoundTripsThroughTheRuntimeModel() {
    let chosen = choice(.siliconFlow, "Qwen/Qwen3-8B")
    #expect(chosen.runtimeModel == "siliconFlow/Qwen/Qwen3-8B")
    #expect(ModelChoice(runtimeModel: chosen.runtimeModel) == chosen)
    #expect(ModelChoice(runtimeModel: "no-provider") == nil)
  }

  @Test func settingsRoundTripWithoutTheKey() throws {
    var models = settings(.kimi, models: ["kimi-k3"])
    models.toolModel = choice(.kimi, "kimi-k3")
    models.translation.model = choice(.kimi, "kimi-k3")
    let data = try JSONEncoder().encode(models)
    #expect(try JSONDecoder().decode(ModelSettings.self, from: data) == models)
  }

  @Test func oldKeyPointAndImportChoicesWithARuntimeFollowTheSettings() throws {
    let keyPoints = Data(#"{"runtime":{"provider":"codex"},"count":"few"}"#.utf8)
    #expect(try JSONDecoder().decode(KeyPointChoice.self, from: keyPoints) == KeyPointChoice(model: nil, count: .few))
    let translating = Data(#"{"language":"fr","runtime":{"provider":"codex"}}"#.utf8)
    #expect(
      try JSONDecoder().decode(ImportChoice.Translating.self, from: translating)
        == ImportChoice.Translating(language: "fr", model: nil))
  }

  @Test func aJobWaitingForAnAgentBeforeNowWaitsForTheModelService() throws {
    let state = Data(#"{"waiting":{"_0":{"agent":{}}}}"#.utf8)
    #expect(try JSONDecoder().decode(Job.State.self, from: state) == .waiting(.modelService))
  }

  private func settings(_ preset: ModelPreset, models: [String]) -> ModelSettings {
    var provider = ModelProvider(preset)
    provider.models = models.map { ProviderModel(id: $0, checked: true) }
    return ModelSettings(providers: [provider])
  }

  private func choice(_ preset: ModelPreset, _ model: String = "deepseek-chat") -> ModelChoice {
    ModelChoice(provider: ModelProviderID(preset), model: model)
  }
}
