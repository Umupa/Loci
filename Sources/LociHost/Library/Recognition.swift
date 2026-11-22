import Foundation
import LociMedia
import LociModel
import LociStore

/// Recognizing speech on this Mac, when the site gave no subtitles.
extension JobRun {
  /// Writes `transcript.json` sentence by sentence as speech is recognized, so the reader sees it grow.
  /// Stopped part way, it carries on after the last sentence written. A video or episode not downloaded yet
  /// is heard from its sound, fetched for the purpose and deleted afterwards unless the media is to be kept.
  func transcribe(_ item: Item) async throws(StageStop) {
    let earlier = try stored { try context.store.transcript(of: item.id) }
    if earlier?.origin == .platform { return }
    let choice = context.choice(of: item.id)
    if choice != nil, choice?.recognition == nil { return }
    let model = choice?.recognition?.model ?? context.speechModel
    guard let modelFile = await context.equipment.modelFile(model) else { throw .wait(.speechModel(model)) }
    let media: URL
    if let file = try stored({ try context.store.mediaFile(of: item.id) }) {
      media = file
    } else if let source = item.source {
      media = try await sound(of: source, at: .transcribe)
    } else {
      throw .failed("the media file is missing")
    }
    try await inTurn(queue.gates.recognition, at: .transcribe) { () async throws(StageStop) in
      try await recognize(
        item, media: media, model: model, language: choice?.recognition?.language, file: modelFile, earlier: earlier)
    }
    if Task.isCancelled || item.isPodcast { return }
    if choice?.keeping == .online { try stored { try context.store.removeWork(named: Self.sound, of: item.id) } }
  }

  /// The sound of a video or episode not downloaded, fetched once into the work folder.
  func sound(of source: URL, at stage: Job.Stage) async throws(StageStop) -> URL {
    if let fetched = try stored({ try context.store.workFile(named: Self.sound, of: item) }) { return fetched }
    let tool = try await context.ytDlp(needing: [.ytDlp, .ffmpeg])
    return try await fetch(source, audio: true, using: tool, at: stage, report: { _, _ in })
  }

  private func recognize(
    _ item: Item, media: URL, model: SpeechModel, language: String?, file: URL, earlier: Transcript?
  ) async throws(StageStop) {
    var transcript = Heard(
      language: earlier?.language ?? language.flatMap(Self.tag), model: model, segments: earlier?.segments ?? [],
      item: item.id, context: context)
    let start = transcript.segments.last?.end ?? .zero
    let report = progress(.transcribe)
    var source = media
    while true {
      do {
        try await listen(to: source, model: file, language: language, from: start, into: &transcript, report: report)
        break
      } catch let error as TranscribeError where error.unreadableMedia && source == media {
        source = try await wav(of: media)
      } catch {
        if Task.isCancelled { return }
        throw .failed((error as? TranscribeError)?.reason ?? String(describing: error))
      }
    }
    if Task.isCancelled { return }
    try await transcript.finish()
    if !item.isPodcast { try stored { try context.store.removeWork(named: Self.wav, of: item.id) } }
    if item.language == nil, let language = transcript.language {
      let tagged = try? Item(
        id: item.id, kind: item.kind, title: item.title, authors: item.authors, source: item.source,
        language: language, contentHash: item.contentHash, site: item.site, published: item.published,
        why: item.why)
      if let tagged { try stored { try context.store.save(tagged) } }
    }
  }

  private func listen(
    to source: URL, model: URL, language: String?, from start: Duration, into transcript: inout Heard,
    report: @Sendable (Fraction?) -> Void
  ) async throws {
    let heard = context.media.transcriber.transcribe(source, model: model, language: language, from: start)
    for try await heard in heard {
      switch heard {
      case .language(let tag): transcript.heard(language: tag)
      case .words(let words): try await transcript.heard(words)
      case .progress(let share): report(share)
      }
    }
  }

  static let wav = "sound.wav"

  /// The sound of media AVFoundation cannot read, taken out with FFmpeg.
  private func wav(of media: URL) async throws(StageStop) -> URL {
    guard let ffmpeg = await context.equipment.executable(.ffmpeg) else { throw .wait(.component(.ffmpeg)) }
    let output = try stored { try context.store.workFolder(of: item) }.appending(path: Self.wav)
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
