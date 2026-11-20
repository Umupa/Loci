import Foundation
import LociModel
import Synchronization
import whisper

/// Recognizes speech with whisper.cpp on its own thread, ten minutes of sound at a time, so a long episode
/// neither holds the cooperative pool nor sits in memory whole.
public struct WhisperTranscriber: Transcribing {
  static let stretch = Duration.seconds(600)

  public init() {}

  public func transcribe(_ media: URL, model: URL, language: String?, from start: Duration)
    -> AsyncThrowingStream<Heard, any Error>
  {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: Heard.self, throwing: (any Error).self)
    let listener = Listener(continuation: continuation)
    continuation.onTermination = { _ in listener.stopped.store(true, ordering: .relaxed) }
    let thread = Thread {
      do {
        try Self.recognize(media, model: model, language: language, from: start, listener: listener)
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    thread.stackSize = 8 << 20
    thread.start()
    return stream
  }

  private static func recognize(
    _ media: URL, model: URL, language spoken: String?, from start: Duration, listener: Listener
  ) throws(TranscribeError) {
    let audio = try AudioSamples(media)
    let total = audio.duration
    listener.total.store(total.roundedMillisecondsValue, ordering: .relaxed)
    var contextParameters = whisper_context_default_params()
    contextParameters.use_gpu = true
    guard let context = whisper_init_from_file_with_params(model.path(percentEncoded: false), contextParameters) else {
      throw TranscribeError(reason: "the speech model could not be loaded; download it again")
    }
    defer { whisper_free(context) }
    let named = spoken.map { String($0.split(separator: "-").first ?? "").lowercased() }
    var language: UnsafeMutablePointer<CChar>? = strdup(named ?? "auto")
    defer { free(language) }
    var offset = start
    while offset < total, !listener.stopped.load(ordering: .relaxed) {
      let samples = try audio.read(from: offset, length: stretch)
      guard !samples.isEmpty else { break }
      listener.offset.store(offset.roundedMillisecondsValue, ordering: .relaxed)
      listener.length.store(samples.count * 1000 / Int(AudioSamples.rate), ordering: .relaxed)
      var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
      parameters.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
      parameters.token_timestamps = true
      parameters.print_progress = false
      parameters.print_realtime = false
      parameters.print_timestamps = false
      parameters.language = UnsafePointer(language)
      let opaque = Unmanaged.passUnretained(listener).toOpaque()
      parameters.new_segment_callback = { context, _, count, data in
        guard let context, let data else { return }
        Unmanaged<Listener>.fromOpaque(data).takeUnretainedValue().heard(context, newSegments: Int(count))
      }
      parameters.new_segment_callback_user_data = opaque
      parameters.progress_callback = { _, _, percent, data in
        guard let data else { return }
        Unmanaged<Listener>.fromOpaque(data).takeUnretainedValue().progressed(percent: Int(percent))
      }
      parameters.progress_callback_user_data = opaque
      parameters.abort_callback = { data in
        guard let data else { return false }
        return Unmanaged<Listener>.fromOpaque(data).takeUnretainedValue().stopped.load(ordering: .relaxed)
      }
      parameters.abort_callback_user_data = opaque
      let status = samples.withUnsafeBufferPointer { buffer in
        whisper_full(context, parameters, buffer.baseAddress, Int32(buffer.count))
      }
      if listener.stopped.load(ordering: .relaxed) { return }
      guard status == 0 else { throw TranscribeError(reason: "speech recognition failed (\(status))") }
      if offset == start, named == nil, let detected = whisper_lang_str(whisper_full_lang_id(context)) {
        let tag = String(cString: detected)
        listener.continuation.yield(.language(tag))
        free(language)
        language = strdup(tag)
      }
      offset += stretch
    }
  }
}

/// What the C callbacks reach through their `user_data`.
private final class Listener: Sendable {
  let continuation: AsyncThrowingStream<Heard, any Error>.Continuation
  let stopped = Atomic<Bool>(false)
  /// Where the stretch being recognized starts, its length, and the whole length, in milliseconds.
  let offset = Atomic<Int>(0)
  let length = Atomic<Int>(0)
  let total = Atomic<Int>(0)

  init(continuation: AsyncThrowingStream<Heard, any Error>.Continuation) {
    self.continuation = continuation
  }

  func progressed(percent: Int) {
    let total = self.total.load(ordering: .relaxed)
    guard total > 0 else { return }
    let done = offset.load(ordering: .relaxed) + length.load(ordering: .relaxed) * percent / 100
    continuation.yield(.progress(Fraction(Double(done) / Double(total))))
  }

  func heard(_ context: OpaquePointer, newSegments count: Int) {
    let segments = Int(whisper_full_n_segments(context))
    let base = offset.load(ordering: .relaxed)
    var words = WordJoiner()
    for segment in max(0, segments - count)..<segments {
      for index in 0..<Int(whisper_full_n_tokens(context, Int32(segment))) {
        let token = whisper_full_get_token_data(context, Int32(segment), Int32(index))
        guard token.id < whisper_token_eot(context),
          let text = whisper_full_get_token_text(context, Int32(segment), Int32(index))
        else { continue }
        let bytes = Array(UnsafeBufferPointer(start: text, count: strlen(text))).map { UInt8(bitPattern: $0) }
        words.add(
          bytes, start: .milliseconds(base + Int(token.t0) * 10), end: .milliseconds(base + Int(token.t1) * 10))
      }
    }
    let heard = words.finish()
    if !heard.isEmpty { continuation.yield(.words(heard)) }
  }
}
