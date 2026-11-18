import AVFoundation
import Foundation
import Synchronization

/// The sound of a media file as Whisper hears it: 16 kHz, one channel, 32-bit floats, read a stretch at a
/// time so a long episode never sits in memory whole. Blocks while it decodes.
struct AudioSamples {
  static let rate = 16_000.0
  private let file: AVAudioFile
  private let target: AVAudioFormat

  init(_ url: URL) throws(TranscribeError) {
    do {
      file = try AVAudioFile(forReading: url)
    } catch {
      throw TranscribeError(reason: error.localizedDescription, unreadableMedia: true)
    }
    guard
      let target = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Self.rate, channels: 1, interleaved: false)
    else { throw TranscribeError(reason: "no format for recognition") }
    self.target = target
  }

  var duration: Duration {
    .milliseconds(Int(Double(file.length) / file.processingFormat.sampleRate * 1000))
  }

  /// The samples from `start` for `length`; empty past the end.
  func read(from start: Duration, length: Duration) throws(TranscribeError) -> [Float] {
    let sourceRate = file.processingFormat.sampleRate
    let first = AVAudioFramePosition(Double(start.roundedMillisecondsValue) / 1000 * sourceRate)
    guard first < file.length else { return [] }
    let count = AVAudioFrameCount(
      min(Double(length.roundedMillisecondsValue) / 1000 * sourceRate, Double(file.length - first)))
    guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count),
      let converter = AVAudioConverter(from: file.processingFormat, to: target),
      let converted = AVAudioPCMBuffer(
        pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(count) * Self.rate / sourceRate) + 1024)
    else { throw TranscribeError(reason: "cannot prepare the sound for recognition") }
    do {
      file.framePosition = first
      try file.read(into: source, frameCount: count)
    } catch {
      throw TranscribeError(reason: error.localizedDescription, unreadableMedia: true)
    }
    let pending = OneBuffer(source)
    var failure: NSError?
    converter.convert(to: converted, error: &failure) { _, status in
      let next = pending.take()
      status.pointee = next == nil ? .endOfStream : .haveData
      return next
    }
    if let failure { throw TranscribeError(reason: failure.localizedDescription, unreadableMedia: true) }
    guard let channel = converted.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
  }
}

/// The one buffer a conversion reads, handed over once.
private final class OneBuffer: Sendable {
  private let buffer: Mutex<AVAudioPCMBuffer?>

  init(_ buffer: sending AVAudioPCMBuffer) {
    self.buffer = Mutex(buffer)
  }

  func take() -> AVAudioPCMBuffer? {
    buffer.withLock { buffer in
      let taken = buffer
      buffer = nil
      return taken
    }
  }
}
