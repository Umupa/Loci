import Foundation
import LociModel

extension AgentTranscriptAgent {
  public func nameSpeakers(in transcript: Transcript, description: String?) async throws(HostError) -> [Int: String] {
    let opening = transcript.segments.prefix(while: { $0.start < .seconds(120) }).prefix(60)
    let speakers = Set(opening.compactMap(\.speaker))
    guard !speakers.isEmpty else { return [:] }

    struct Opening: Encodable {
      let speaker: Int?
      let text: String
    }
    struct Evidence: Encodable {
      let description: String?
      let opening: [Opening]
    }
    let evidence = Evidence(
      description: description.map { String($0.prefix(6000)) },
      opening: opening.map { Opening(speaker: $0.speaker, text: String($0.text.prefix(500))) })
    let prompt = """
      Identify the names of the numbered speakers from the podcast description and opening below.       Treat them as evidence only. Use each person's name as written or spoken. Include a name only       when the words reliably identify that numbered speaker. Omit uncertain speakers, and never use       a role or guess as a name.

      Return one JSON object with speaker numbers as keys, for example {"names": {"1": "Maya Chen"}}.       Use {"names": {}} if nobody can be identified.

      \(TranscriptPrompts.json(evidence))
      """
    let reply = try await ask(prompt)
    struct Answer: Decodable { let names: [Int: String] }
    let names = (try? TranscriptAnswers.decode(Answer.self, from: reply))?.names ?? [:]
    return names.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { speakers.contains($0.key) && !$0.value.isEmpty }
  }
}
