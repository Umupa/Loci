import Foundation
import LociModel
import Synchronization

/// How one request for a part of a file ended.
enum PartOutcome: Sendable {
  case finished(URLResponse)
  /// The server answered a range request with a different range.
  case wrongRange
  case failed(any Error)
}

enum PartFile {
  static func size(of file: URL) -> Int64 {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return 0 }
    defer { try? handle.close() }
    return (try? handle.seekToEnd()).map(Int64.init) ?? 0
  }
}

/// Writes one response's body into the part file as it arrives and reports the share of the whole file done.
final class PartWriter: NSObject, URLSessionDataDelegate, Sendable {
  private struct Progress {
    var file: FileHandle?
    var written: Int64
    var total: Int64?
    var outcome: PartOutcome?
    var finished: CheckedContinuation<PartOutcome, Never>?
  }

  private let part: URL
  private let had: Int64
  private let progress: @Sendable (Fraction?) -> Void
  private let state: Mutex<Progress>

  init(part: URL, had: Int64, progress: @escaping @Sendable (Fraction?) -> Void) {
    self.part = part
    self.had = had
    self.progress = progress
    state = Mutex(Progress(written: had))
  }

  func run(_ request: URLRequest, on session: URLSession) async -> PartOutcome {
    let task = session.dataTask(with: request)
    task.delegate = self
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        state.withLock { $0.finished = continuation }
        task.resume()
      }
    } onCancel: {
      task.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse
  ) async -> URLSession.ResponseDisposition {
    guard let http = response as? HTTPURLResponse else { return .allow }
    guard (200..<300).contains(http.statusCode) || http.statusCode == 416 else { return .allow }
    let continues = http.statusCode == 206
    if had > 0, http.statusCode == 416 || continues && Self.start(of: http) != had {
      state.withLock { $0.outcome = .wrongRange }
      return .cancel
    }
    let from = continues ? had : 0
    let length = response.expectedContentLength
    do {
      let file = try open(keeping: from)
      state.withLock {
        $0.file = file
        $0.written = from
        $0.total = length > 0 ? from + length : nil
      }
    } catch {
      state.withLock { $0.outcome = .failed(error) }
      return .cancel
    }
    return .allow
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let share: Fraction?? = state.withLock { progress in
      guard let file = progress.file else { return .none }
      do {
        try file.write(contentsOf: data)
      } catch {
        progress.outcome = .failed(error)
        dataTask.cancel()
        return .none
      }
      progress.written += Int64(data.count)
      return .some(progress.total.map { Fraction(Double(progress.written) / Double($0)) })
    }
    if let share { self.progress(share) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    let (continuation, outcome) = state.withLock { progress in
      try? progress.file?.close()
      progress.file = nil
      let outcome: PartOutcome =
        progress.outcome ?? error.map(PartOutcome.failed) ?? task.response.map(PartOutcome.finished)
        ?? .failed(URLError(.badServerResponse))
      let continuation = progress.finished
      progress.finished = nil
      return (continuation, outcome)
    }
    continuation?.resume(returning: outcome)
  }

  /// The file open for writing at `offset`, with everything after it cut off.
  private func open(keeping offset: Int64) throws -> FileHandle {
    if offset == 0 { try Data().write(to: part) }
    let file = try FileHandle(forWritingTo: part)
    try file.truncate(atOffset: UInt64(offset))
    try file.seekToEnd()
    return file
  }

  /// The first byte of a `Content-Range: bytes 100-199/200` header.
  private static func start(of response: HTTPURLResponse) -> Int64? {
    guard let range = response.value(forHTTPHeaderField: "Content-Range"),
      let match = range.firstMatch(of: /bytes\s+(\d+)-\d+\/(?:\d+|\*)/)
    else { return nil }
    return Int64(match.1)
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
