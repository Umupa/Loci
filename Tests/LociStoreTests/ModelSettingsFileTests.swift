import Foundation
import LociModel
import Testing

@testable import LociStore

struct ModelSettingsFileTests {
  @Test func anOldSettingsFileBecomesOneProviderUsedForTranslationAndTranscripts() throws {
    try withStore { store in
      try store.writeFile(
        "model-settings.json",
        #"{"service":{"provider":"deepSeek","model":"deepseek-chat"},"translation":{"language":"ja","smart":true,"#
          + #""transcriptPrompt":"T {{language}}","articlePrompt":"A {{language}}"}}"#)
      let settings = try store.modelSettings()
      let provider = try #require(settings.providers.first)
      #expect(settings.providers.count == 1)
      #expect(provider.preset == .deepSeek)
      #expect(provider.enabled)
      #expect(provider.models == [ProviderModel(id: "deepseek-chat", checked: true)])
      let chosen = ModelChoice(provider: ModelProviderID(.deepSeek), model: "deepseek-chat")
      #expect(settings.toolModel == chosen)
      #expect(settings.translation.model == nil)
      #expect(settings.translation.language == "ja")
      #expect(settings.translation.transcriptPrompt == "T {{language}}")
      #expect(try store.readFile("model-settings.json").contains("providers"))
      #expect(try store.modelSettings() == settings)
    }
  }

  @Test func aMigratedProviderKeepsTheOldKeychainAccount() throws {
    try withStore { store in
      try store.writeFile(
        "model-settings.json",
        #"{"service":{"provider":"compatible","model":"local","baseURL":"https:\/\/models.example.test\/v1\/"}}"#)
      let compatible = try #require(try store.modelSettings().providers.first)
      #expect(compatible.preset == .custom)
      #expect(compatible.api == .openAI)
      #expect(compatible.address == ModelAddress("https://models.example.test/v1/"))
      #expect(compatible.keyAccount == "compatible:https://models.example.test/v1/chat/completions")
    }
    for (provider, account) in [
      ("openAI", "openAI:https://api.openai.com/v1/chat/completions"),
      ("anthropic", "anthropic:https://api.anthropic.com/v1/messages"),
      ("openRouter", "openRouter:https://openrouter.ai/api/v1/chat/completions"),
      ("deepSeek", "deepSeek:https://api.deepseek.com/chat/completions"),
    ] {
      try withStore { store in
        try store.writeFile("model-settings.json", #"{"service":{"provider":"\#(provider)","model":"m"}}"#)
        #expect(try store.modelSettings().providers.first?.keyAccount == account)
      }
    }
  }

  @Test func anOldFileWithoutAServiceKeepsTheTranslationSettings() throws {
    try withStore { store in
      try store.writeFile(
        "model-settings.json",
        #"{"service":{"provider":"compatible","model":"m","baseURL":"http:\/\/far.example.test"},"#
          + #""translation":{"language":"de","smart":false,"transcriptPrompt":"T","articlePrompt":"A"}}"#)
      let settings = try store.modelSettings()
      #expect(settings.providers.isEmpty)
      #expect(settings.translation.language == "de")
    }
  }

  @Test func settingsReadBackAfterSaving() throws {
    try withStore { store in
      #expect(try store.modelSettings() == ModelSettings())
      var provider = ModelProvider(.kimi)
      provider.models = [ProviderModel(id: "kimi-k3", checked: true), ProviderModel(id: "kimi-k2", checked: false)]
      let settings = ModelSettings(providers: [provider], translation: TranslationSettings(language: "fr"))
      try store.saveModelSettings(settings)
      #expect(try store.modelSettings() == settings)
    }
  }
}
