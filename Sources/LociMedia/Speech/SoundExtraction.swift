import Foundation

/// Takes the sound out of media AVFoundation cannot read, such as WebM or Matroska, as a WAV file the
/// recognizer can.
public enum SoundExtraction {
  public static func wav(from media: URL, to output: URL, ffmpeg: URL, runner: any ProgramRunner)
    async throws(TranscribeError)
  {
    let call = ProgramCall(
      executable: ffmpeg,
      arguments: [
        "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", media.path(percentEncoded: false), "-vn",
        "-ac", "1", "-ar", "16000", output.path(percentEncoded: false),
      ])
    let result: ProgramResult
    do {
      result = try await runner.run(call)
    } catch {
      throw TranscribeError(reason: error.reason)
    }
    guard result.succeeded else { throw TranscribeError(reason: result.diagnostics, unreadableMedia: true) }
  }
}
