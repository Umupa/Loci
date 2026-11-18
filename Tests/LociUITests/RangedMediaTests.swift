import AVFoundation
import Foundation
import LociModel
import Synchronization
import Testing

@testable import LociUI

/// R-S6: media downloaded on another Mac plays by reading ranges of it from that Mac's host.
@MainActor
struct RangedMediaTests {
  /// Two seconds of silence as a WAV file: 16-bit mono at 8 kHz.
  static let twoSeconds: Data = {
    let rate: UInt32 = 8_000
    let samples = Data(count: Int(rate) * 2 * 2)
    var header = Data()
    func append(_ text: String) { header.append(contentsOf: Array(text.utf8)) }
    func append<T: FixedWidthInteger>(_ value: T) {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }
    append("RIFF")
    append(UInt32(36 + samples.count))
    append("WAVEfmt ")
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(rate)
    append(rate * 2)
    append(UInt16(2))
    append(UInt16(16))
    append("data")
    append(UInt32(samples.count))
    return header + samples
  }()

  @Test func aRequestIsReadInChunksUpToWhereItEnds() {
    let chunk = Int64(RangedMedia.chunk)
    let ranges = RangedMedia.chunks(from: 100, to: 100 + chunk + 10)

    #expect(ranges.map(\.offset) == [100, 100 + chunk])
    #expect(ranges.map(\.length) == [RangedMedia.chunk, 10])
  }

  @Test func mediaOnAnotherMacPlaysThroughItsHost() async throws {
    let host = BytesHost(bytes: Self.twoSeconds)
    let source = await PlayerSource.of(.downloaded, item: EntityID(), on: host)
    guard case .ranges(let media) = source else {
      Issue.record("expected ranges, got \(String(describing: source))")
      return
    }

    let duration = try await media.asset().load(.duration)

    #expect(abs(duration.seconds - 2) < 0.01)
    #expect(host.reads.withLock { $0 } > 0)
  }
}

/// A host on another Mac with one downloaded file and nothing else.
private final class BytesHost: LociModel.Host {
  let bytes: Data
  let reads = Mutex(0)

  init(bytes: Data) {
    self.bytes = bytes
  }

  func run<C: Command>(_ command: C) async throws(HostError) -> C.Reply {
    let reply: Any
    switch command {
    case is ReadMediaFileInfo:
      reply = MediaFileInfo(byteCount: Int64(bytes.count), fileExtension: "wav")
    case let read as ReadMediaBytes:
      reads.withLock { $0 += 1 }
      let start = min(Int(read.offset), bytes.count)
      reply = bytes.subdata(in: start..<min(start + read.length, bytes.count))
    default:
      throw .offline
    }
    guard let typed = reply as? C.Reply else { throw .offline }
    return typed
  }

  func subscribe<S: Subscription>(_ subscription: S) -> AsyncStream<Feed<S.Value>> {
    AsyncStream { $0.finish() }
  }

  func upload(_ file: LocalFile) async throws(HostError) -> Upload { throw .offline }

  func localFile(_ place: LocalPlace) async -> LocalFile? { nil }
}
