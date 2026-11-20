import Foundation
import LociModel
import Synchronization

/// Turns yt-dlp's progress lines into one share that only grows, and the bytes so far of all files. A video
/// arrives as picture then sound, two files in turn; the picture is most of the bytes, so it counts for nine
/// tenths.
final class DownloadProgress: Sendable {
  private let audio: Bool
  private let report: @Sendable (Fraction?, Job.Amount?) -> Void
  private let state = Mutex<State>(State())

  private struct State {
    var files: [String] = []
    var best: Double = 0
    var bytes: [String: (done: Int64, total: Int64?)] = [:]

    var amount: Job.Amount? {
      guard !bytes.isEmpty else { return nil }
      let totals = bytes.values.map(\.total)
      let total = totals.contains { $0 == nil } ? nil : totals.compactMap { $0 }.reduce(0, +)
      return Job.Amount(done: bytes.values.map(\.done).reduce(0, +), total: total)
    }
  }

  init(audio: Bool, report: @escaping @Sendable (Fraction?, Job.Amount?) -> Void) {
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
    let heard: (share: Double?, amount: Job.Amount?)? = state.withLock { state in
      if let file = progress.filename, !state.files.contains(file) { state.files.append(file) }
      if let file = progress.filename, let done = progress.downloadedBytes {
        state.bytes[file] = (Int64(done), total.map { Int64($0) })
      }
      guard let part else { return (nil, state.amount) }
      let index = max(state.files.count - 1, 0)
      let overall = audio ? part : (index == 0 ? part * 0.9 : 0.9 + part * 0.1)
      guard overall >= state.best else { return nil }
      state.best = overall
      return (overall, state.amount)
    }
    guard let heard else { return }
    report(heard.share.map(Fraction.init), heard.amount)
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
