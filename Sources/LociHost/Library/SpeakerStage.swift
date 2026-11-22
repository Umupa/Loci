import Foundation
import LociMedia
import LociModel
import LociStore
import os

extension JobRun {
  func diarize(_ item: Item) async {
    let store = context.store
    let choice = context.choice(of: item.id)
    defer {
      if !Task.isCancelled {
        try? store.removeWork(named: Self.wav, of: item.id)
        if choice?.keeping == .online { try? store.removeWork(named: Self.sound, of: item.id) }
      }
    }

    do {
      guard let diarizer = context.media.diarizer,
        let transcript = try store.transcript(of: item.id), !transcript.segments.isEmpty,
        transcript.speakers.isEmpty
      else { return }
      let audio = try await audioForSpeakers(of: item)
      let models = await context.equipment.modelsFolder
      let report = progress(.diarize)
      let turns = try await inTurn(queue.gates.recognition, at: .diarize) { () async throws(StageStop) in
        do {
          try Task.checkCancellation()
          return try await diarizer.speakers(in: audio, models: models) { report($0) }
        } catch {
          throw .failed(error.localizedDescription)
        }
      }
      let labeled = try SpeakerTurn.label(transcript, from: turns)
      guard !Task.isCancelled, !labeled.speakers.isEmpty else { return }
      let names = await nameSpeakers(in: labeled)
      let named = try Transcript(
        language: labeled.language, origin: labeled.origin, segments: labeled.segments, speakerNames: names)
      try await queue.saveSpeakerLabels(named, replacing: transcript, of: item.id)
    } catch {
      if !Task.isCancelled {
        Logger(subsystem: "Loci", category: "library").warning(
          "could not distinguish speakers in \(item.id.description, privacy: .public): \(String(describing: error), privacy: .public)"
        )
      }
    }
  }

  private func audioForSpeakers(of item: Item) async throws(StageStop) -> URL {
    if let local = try stored({
      try context.store.workFile(named: Self.wav, of: item.id) ?? context.store.mediaFile(of: item.id)
    }) {
      return local
    }
    guard let source = item.source else { throw .failed("the media file is missing") }
    return try await sound(of: source, at: .diarize)
  }

  private func nameSpeakers(in transcript: Transcript) async -> [Int: String] {
    guard let (agent, _) = await context.runtimeWriter(nil) else { return [:] }
    let description = (try? context.store.workText(named: Self.info, of: item))
      .flatMap { try? MediaInfo(json: Data($0.utf8)).description }
    return await queue.gates.agents.through {
      guard !Task.isCancelled else { return [:] }
      return (try? await agent.nameSpeakers(in: transcript, description: description)) ?? [:]
    }
  }
}
