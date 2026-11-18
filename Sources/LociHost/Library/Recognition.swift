import Foundation
import LociMedia
import LociModel
import LociStore

/// Recognizing speech on this Mac, when the site gave no subtitles.
extension JobRun {
  /// Writes `transcript.json` sentence by sentence as speech is recognized, so the reader sees it grow.
  /// Stopped part way, it carries on after the last sentence written.
  func transcribe(_ item: Item) async throws(StageStop) {
    let earlier = try stored { try context.store.transcript(of: item.id) }
    if earlier?.origin == .platform { return }
    guard let media = try stored({ try context.store.mediaFile(of: item.id) }) else {
      throw .failed("the media file is missing")
    }
    let model = context.speechModel
    guard let modelFile = await context.equipment.modelFile(model) else { throw .wait(.speechModel(model)) }
    try await inTurn(queue.gates.recognition, at: .transcribe) { () async throws(StageStop) in
      try await recognize(item, media: media, model: model, file: modelFile, earlier: earlier)
    }
  }

  private func recognize(_ item: Item, media: URL, model: SpeechModel, file: URL, earlier: Transcript?)
    async throws(StageStop)
  {
    var transcript = Heard(
      language: earlier?.language, model: model, segments: earlier?.segments ?? [], item: item.id, context: context)
    let start = transcript.segments.last?.end ?? .zero
    let report = progress(.transcribe)
    var source = media
    while true {
      do {
        try await listen(to: source, model: file, from: start, into: &transcript, report: report)
        break
      } catch let error as TranscribeError where error.unreadableMedia && source == media {
        source = try await sound(of: media)
      } catch {
        if Task.isCancelled { return }
        throw .failed((error as? TranscribeError)?.reason ?? String(describing: error))
      }
    }
    if Task.isCancelled { return }
    try await transcript.finish()
    try stored { try context.store.clearWork(of: item.id) }
    if item.language == nil, let language = transcript.language {
      let tagged = try? Item(
        id: item.id, kind: item.kind, title: item.title, authors: item.authors, source: item.source,
        language: language, contentHash: item.contentHash, site: item.site, published: item.published)
      if let tagged { try stored { try context.store.save(tagged) } }
    }
  }

  private func listen(
    to source: URL, model: URL, from start: Duration, into transcript: inout Heard,
    report: @Sendable (Fraction?) -> Void
  ) async throws {
    for try await heard in context.media.transcriber.transcribe(source, model: model, from: start) {
      switch heard {
      case .language(let tag): transcript.heard(language: tag)
      case .words(let words): try await transcript.heard(words)
      case .progress(let share): report(share)
      }
    }
  }

  /// The sound of media AVFoundation cannot read, taken out with FFmpeg.
  private func sound(of media: URL) async throws(StageStop) -> URL {
    guard let ffmpeg = await context.equipment.executable(.ffmpeg) else { throw .wait(.component(.ffmpeg)) }
    let output = try stored { try context.store.workFolder(of: item) }.appending(path: "sound.wav")
    do throws(TranscribeError) {
      try await SoundExtraction.wav(from: media, to: output, ffmpeg: ffmpeg, runner: context.media.runner)
    } catch {
      throw .failed(error.reason, nil)
    }
    return output
  }
}

/// The transcript as it grows: finished sentences are written at once, the one still being spoken waits.
private struct Heard {
  var language: String?
  let model: SpeechModel
  var segments: [Transcript.Segment]
  let item: EntityID
  let context: LibraryContext
  private var pending: [SpokenWord] = []
  private let segmenter = Segmenter()

  init(language: String?, model: SpeechModel, segments: [Transcript.Segment], item: EntityID, context: LibraryContext) {
    self.language = language
    self.model = model
    self.segments = segments
    self.item = item
    self.context = context
  }

  mutating func heard(language tag: String) {
    if language == nil { language = JobRun.tag(tag) }
  }

  mutating func heard(_ words: [SpokenWord]) async throws(StageStop) {
    pending += words
    let (finished, rest) = segmenter.finished(pending)
    pending = rest
    guard !finished.isEmpty else { return }
    segments += finished
    try await save()
  }

  mutating func finish() async throws(StageStop) {
    segments += segmenter.segments(pending)
    pending = []
    try await save()
  }

  private func save() async throws(StageStop) {
    let transcript = try stored { try Transcript(language: language, origin: .recognized(model), segments: segments) }
    try stored { try context.store.save(transcript, of: item) }
    await context.notify([.job(item)])
  }
}
