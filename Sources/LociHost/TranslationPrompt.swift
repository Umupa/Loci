import Foundation
import LociModel
import LociStore

public struct TranslationPrompt: Sendable {
  public enum Kind: String, Sendable {
    case transcript, article
  }

  public let kind: Kind
  public let language: String
  let instructions: String
  private let context: String?
  let cacheIdentity: [String]

  init(kind: Kind, language: String, instructions: String, context: [String]? = nil) {
    self.kind = kind
    self.language = language
    self.instructions = instructions.replacing("{{language}}", with: language)
    let context = context.map { TranscriptPrompts.json(["context": $0]) }
    self.context = context
    cacheIdentity = ["1", kind.rawValue, language, instructions, TranslationCacheKey([context ?? ""]).digest]
  }

  func request(for input: [String]) -> String {
    let background =
      context.map {
        """

        Use this complete source as context for terminology and meaning. Translate only the separate input below.
        \($0)

        """
      } ?? ""
    return """
      \(instructions)
      \(background)
      Translate into the language with BCP 47 tag `\(language)`.
      Return one translation per input in the same order, exactly \(input.count), none empty.
      Return only one JSON object, no prose around it: {"lines": ["…", …]}

      The input:
      \(TranscriptPrompts.json(["lines": input]))
      """
  }
}
