import Foundation
import LociModel
import Synchronization

/// Turns yt-dlp's progress lines into one share that only grows. A video arrives as picture then sound, two
/// files in turn; the picture is most of the bytes, so it counts for nine tenths.
final class DownloadProgress: Sendable {
  private let audio: Bool
  private let report: @Sendable (Fraction?) -> Void
  private let state = Mutex<(files: [String], best: Double)>(([], 0))

  init(audio: Bool, report: @escaping @Sendable (Fraction?) -> Void) {
    self.audio = audio
    self.report = report
  }

  func hear(_ line: String) {
    guard line.hasPrefix("[loci] "), let data = line.dropFirst(7).data(using: .utf8),
      let progress = try? Self.decoder.decode(Line.self, from: data)
    else { return }
    let total = progress.totalBytes ?? progress.totalBytesEstimate
    let part: Double? =
      if let total, total > 0, let done = progress.downloadedBytes {
        min(done / total, 1)
      } else if let index = progress.fragmentIndex, let count = progress.fragmentCount, count > 0 {
        min(Double(index) / Double(count), 1)
      } else {
        nil
      }
    let share: Double?? = state.withLock { state in
      if let file = progress.filename, !state.files.contains(file) { state.files.append(file) }
      guard let part else { return .some(nil) }
      let index = max(state.files.count - 1, 0)
      let overall = audio ? part : (index == 0 ? part * 0.9 : 0.9 + part * 0.1)
      guard overall >= state.best else { return .none }
      state.best = overall
      return .some(overall)
    }
    guard let share else { return }
    report(share.map(Fraction.init))
  }

  private static let decoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  private struct Line: Decodable {
    let filename: String?
    let downloadedBytes: Double?
    let totalBytes: Double?
    let totalBytesEstimate: Double?
    let fragmentIndex: Int?
    let fragmentCount: Int?
  }
}
