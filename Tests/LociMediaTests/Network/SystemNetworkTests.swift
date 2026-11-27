import Foundation
import LociMedia
import LociModel
import Synchronization
import Testing

struct SystemNetworkTests {
  private static let body = Data((0..<4096).map { UInt8($0 % 251) })

  private static func chunks(of data: Data, size: Int = 1024) -> [Data] {
    stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
  }

  @Test func progressFollowsTheBytesReceived() async throws {
    let address = ScriptedServer.host(answering: [
      .init(headers: ["Content-Length": "\(Self.body.count)"], chunks: Self.chunks(of: Self.body))
    ])
    let heard = Mutex<[Fraction?]>([])
    let file = try await SystemNetwork(session: ScriptedServer.session()).download(URLRequest(url: address)) { share in
      heard.withLock { $0.append(share) }
    }
    #expect(try Data(contentsOf: file) == Self.body)
    let shares = heard.withLock { $0 }.compactMap { $0?.value }
    #expect(shares.contains { $0 > 0 && $0 < 1 })
    #expect(shares.last == 1)
  }

  @Test func aResumedDownloadAsksForTheRestAndAppendsIt() async throws {
    let rest = Self.body.subdata(in: 1000..<Self.body.count)
    let address = ScriptedServer.host(answering: [
      .init(
        status: 206,
        headers: ["Content-Length": "\(rest.count)", "Content-Range": "bytes 1000-4095/4096"],
        chunks: Self.chunks(of: rest))
    ])
    let part = try Self.part(holding: Self.body.prefix(1000))
    let heard = Mutex<[Fraction?]>([])
    let file = try await SystemNetwork(session: ScriptedServer.session()).download(
      URLRequest(url: address), keepingPartAt: part
    ) { share in heard.withLock { $0.append(share) } }
    #expect(file == part)
    #expect(try Data(contentsOf: file) == Self.body)
    #expect(ScriptedServer.requests(to: address).map { $0.value(forHTTPHeaderField: "Range") } == ["bytes=1000-"])
    #expect(heard.withLock { $0 }.compactMap { $0?.value }.first.map { $0 > 0.24 } == true)
  }

  @Test func whatArrivedBeforeTheConnectionDroppedIsKeptForTheNextTry() async throws {
    let address = ScriptedServer.host(answering: [
      .init(headers: ["Content-Length": "\(Self.body.count)"], chunks: [Self.body.prefix(1500)], drops: true)
    ])
    let part = URL.temporaryDirectory.appending(path: "part-\(UUID().uuidString)")
    await #expect(throws: FetchError.self) {
      try await SystemNetwork(session: ScriptedServer.session()).download(
        URLRequest(url: address), keepingPartAt: part
      ) { _ in }
    }
    #expect(try Data(contentsOf: part) == Self.body.prefix(1500))
  }

  @Test func aServerThatIgnoresTheRangeStartsOver() async throws {
    let address = ScriptedServer.host(answering: [
      .init(headers: ["Content-Length": "\(Self.body.count)"], chunks: Self.chunks(of: Self.body))
    ])
    let part = try Self.part(holding: Data(repeating: 9, count: 700))
    let file = try await SystemNetwork(session: ScriptedServer.session()).download(
      URLRequest(url: address), keepingPartAt: part
    ) { _ in }
    #expect(try Data(contentsOf: file) == Self.body)
  }

  @Test func aMismatchedContentRangeStartsOver() async throws {
    let address = ScriptedServer.host(answering: [
      .init(status: 206, headers: ["Content-Range": "bytes 0-4095/4096"], chunks: Self.chunks(of: Self.body)),
      .init(headers: ["Content-Length": "\(Self.body.count)"], chunks: Self.chunks(of: Self.body)),
    ])
    let part = try Self.part(holding: Self.body.prefix(1000))
    let file = try await SystemNetwork(session: ScriptedServer.session()).download(
      URLRequest(url: address), keepingPartAt: part
    ) { _ in }
    #expect(try Data(contentsOf: file) == Self.body)
    #expect(ScriptedServer.requests(to: address).map { $0.value(forHTTPHeaderField: "Range") } == ["bytes=1000-", nil])
  }

  @Test func aDownloadGivesUpOnlyAfterTheStallWithNoBytes() async throws {
    let address = ScriptedServer.host(answering: [.init(chunks: Self.chunks(of: Self.body))])
    let session = ScriptedServer.session()
    _ = try await SystemNetwork(session: session, stall: .seconds(7)).download(URLRequest(url: address)) { _ in }
    #expect(ScriptedServer.requests(to: address).map(\.timeoutInterval) == [7])
    #expect(session.configuration.timeoutIntervalForResource >= 7 * 24 * 60 * 60)
  }

  private static func part(holding data: Data) throws -> URL {
    let part = URL.temporaryDirectory.appending(path: "part-\(UUID().uuidString)")
    try data.write(to: part)
    return part
  }
}
