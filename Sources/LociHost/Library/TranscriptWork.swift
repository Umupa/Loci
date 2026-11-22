import LociModel
import LociStore

struct TranscriptWork: Sendable {
  let agent: any TranscriptAgent
  let parallelism: Int
  let usesRuntime: Bool
  let identity: [String]
  let settings: TranslationSettings
  let cache: TranslationCache

  func prompt(_ kind: TranslationPrompt.Kind, language: String, source: [String]) -> TranslationPrompt {
    TranslationPrompt(
      kind: kind, language: language,
      instructions: kind == .article ? settings.articlePrompt : settings.transcriptPrompt,
      context: settings.smart ? source : nil)
  }

  func translate(_ input: [String], using prompt: TranslationPrompt) async throws(HostError) -> [String] {
    try await cache.translate(input, keyedBy: identity + prompt.cacheIdentity) { batch async throws(HostError) in
      try await agent.translate(batch, using: prompt)
    }
  }
}
