import Foundation
import LociModel

/// Recognizes speech on this Mac. The app's version runs whisper.cpp; tests hear what they script.
public protocol Transcribing: Sendable {
  /// What is said in `media` from `start` on, in order, as it is recognized, hearing it as `language` (a BCP 47
  /// tag) or telling the language when that is `nil`. Ending the stream stops the work.
  func transcribe(_ media: URL, model: URL, language: String?, from start: Duration)
    -> AsyncThrowingStream<Heard, any Error>
}

/// One piece of news from recognition.
public enum Heard: Hashable, Sendable {
  /// The spoken language as a BCP 47 tag, said once near the start.
  case language(String)
  /// The next words, in order.
  case words([SpokenWord])
  /// How much of the whole media has been gone through.
  case progress(Fraction)
}

/// Why speech could not be recognized.
public struct TranscribeError: Error, Hashable, Sendable {
  public let reason: String
  /// The media has no sound the recognizer can read; converting it with FFmpeg first may help.
  public let unreadableMedia: Bool

  public init(reason: String, unreadableMedia: Bool = false) {
    self.reason = reason
    self.unreadableMedia = unreadableMedia
  }
}
