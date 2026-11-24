import Foundation
import LociMedia
import LociModel
import LociStore
import Testing

@testable import LociHost

/// M-S7–M-S11, M-S14: providers, their keys, their models, and what each use is done with.
struct ModelServiceTests {
  @Test func showingWhetherAKeyIsSavedNeverReadsTheKey() async throws {
    let keys = MemoryModelKeys(["provider:openAI": "saved-key"])
    try await withModelHost(keys: keys) { host, _, _, _ in
      _ = try await host.saveModelSettings(ModelSettings(providers: [ModelProvider(.openAI), ModelProvider(.kimi)]))
      let state = try await host.readModelSettings()
      #expect(state.keys == [ModelProviderID(.openAI)])
      _ = try await host.run(ReadRuntime())
      _ = try await host.modelOptions()
      #expect(keys.reads == 0)
    }
  }

  @Test func aKeyIsSavedWithoutAModelAndOnlyPreferencesGoToTheDataFolder() async throws {
    try await withModelHost { host, world, _, keys in
      let provider = ModelProvider(.deepSeek)
      _ = try await host.saveModelSettings(ModelSettings(providers: [provider]))
      let saved = try await host.setModelKey("  saved-key \n", for: provider.id)
      #expect(saved.keys == [provider.id])
      #expect(keys.hasKey(account: provider.keyAccount))
      let text = try String(contentsOf: world.place.root.appending(path: "model-settings.json"), encoding: .utf8)
      #expect(!text.contains("saved-key"))
      #expect(try await host.modelKey(for: provider.id) == "saved-key")
      #expect(try await host.setModelKey(nil, for: provider.id).keys.isEmpty)
      #expect(!keys.hasKey(account: provider.keyAccount))
    }
  }

  @Test func eachProviderKeepsItsOwnKeyWhateverItsAddressOrModels() async throws {
    try await withModelHost { host, _, network, _ in
      var openAI = ModelProvider(.openAI)
      openAI.models = [ProviderModel(id: "fixture", checked: true)]
      var own = ModelProvider(custom: EntityID(), api: .openAI)
      own.address = ModelAddress("https://models.example.test/v1")
      own.models = [ProviderModel(id: "local", checked: true)]
      var settings = try await host.saveModelSettings(ModelSettings(providers: [openAI, own])).settings
      _ = try await host.setModelKey("first-key", for: openAI.id)
      _ = try await host.setModelKey("second-key", for: own.id)

      settings.providers[1].address = ModelAddress("https://models.example.test/v2/")
      settings.providers[1].models.append(ProviderModel(id: "bigger", checked: true))
      #expect(try await host.saveModelSettings(settings).keys == [openAI.id, own.id])
      _ = try await host.testModel(nil, on: openAI.id)
      _ = try await host.testModel("bigger", on: own.id)
      #expect(await network.keys == ["Bearer first-key", "Bearer second-key"])
    }
  }

  @Test func fetchedModelsJoinTheListUncheckedAndKeepEarlierChecks() async throws {
    try await withModelHost { host, _, _, _ in
      var provider = ModelProvider(.openAI)
      provider.models = [ProviderModel(id: "fixture", checked: true), ProviderModel(id: "by-hand", checked: true)]
      _ = try await host.saveModelSettings(ModelSettings(providers: [provider]))
      _ = try await host.setModelKey("test-key", for: provider.id)
      let fetched = try await host.fetchModels(for: provider.id)
      #expect(
        fetched.settings.providers[0].models == [
          ProviderModel(id: "fixture", checked: true), ProviderModel(id: "by-hand", checked: true),
          ProviderModel(id: "fixture-mini", checked: false),
        ])
    }
  }

  @Test func tryingAProviderWithoutAKeyOrAModelSaysWhatIsMissing() async throws {
    try await withModelHost { host, _, _, _ in
      let provider = ModelProvider(.openAI)
      _ = try await host.saveModelSettings(ModelSettings(providers: [provider]))
      await #expect(throws: HostError.invalidRequest("Enter an API key.")) {
        try await host.testModel(nil, on: provider.id)
      }
      _ = try await host.setModelKey("test-key", for: provider.id)
      await #expect(throws: HostError.invalidRequest("Add a model first.")) {
        try await host.testModel(nil, on: provider.id)
      }
    }
  }

  @Test func theFirstModelThereIsBecomesWhatEachUseIsDoneWithAndMenusListOnlyUsableOnes() async throws {
    try await withModelHost { host, _, _, _ in
      var off = ModelProvider(.kimi)
      off.models = [ProviderModel(id: "kimi-k3", checked: true)]
      off.enabled = false
      var keyless = ModelProvider(.zhipu)
      keyless.models = [ProviderModel(id: "glm", checked: true)]
      _ = try await host.saveModelSettings(ModelSettings(providers: [off, keyless]))
      _ = try await host.setModelKey("k", for: off.id)
      #expect(try await host.modelOptions().groups.isEmpty)

      let settings = try await configureModels(host)
      let chosen = ModelChoice(provider: ModelProviderID(.openAI), model: "fixture")
      #expect(settings.uses == ModelUses(translation: chosen, transcripts: chosen))
      #expect(try await host.modelOptions().groups.map(\.provider) == [ModelProviderID(.openAI)])
    }
  }

  @Test func upgradingKeepsTheServiceTheModelAndTheKey() async throws {
    let account = "deepSeek:https://api.deepseek.com/chat/completions"
    let keys = MemoryModelKeys([account: "kept-key"])
    try await withModelHost(keys: keys) { host, world, network, _ in
      try Data(#"{"service":{"provider":"deepSeek","model":"deepseek-chat"}}"#.utf8)
        .write(to: world.place.root.appending(path: "model-settings.json"))
      let state = try await host.readModelSettings()
      #expect(state.keys == [ModelProviderID(.deepSeek)])
      let chosen = ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-chat")
      #expect(state.settings.uses == ModelUses(translation: chosen, transcripts: chosen))
      _ = try await host.testModel(nil, on: ModelProviderID(.deepSeek))
      #expect(await network.keys == ["Bearer kept-key"])
    }
  }
}
