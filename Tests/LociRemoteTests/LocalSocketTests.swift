import Foundation
import LociModel
import Testing

@testable import LociRemote

@Suite struct LocalSocketTests {
  /// Unix socket paths are limited to 104 bytes, so the test's socket is not in the long temporary folder.
  private static func path() -> URL {
    URL(filePath: "/tmp/loci-\(UUID().uuidString.prefix(8)).sock")
  }

  private static let call = LocalCall(
    session: .conversation(.main), request: .command(name: "search", body: Data("{}".utf8)))

  @Test func aCallGetsTheAnswerTheAppSends() async throws {
    let path = Self.path()
    defer { unlink(path.path) }
    let serving = Task {
      try await LocalSocket.serve(at: path) { call, reply in
        try? await reply(.value((try? JSONEncoder().encode(call.session?.tag)) ?? Data()))
      }
    }
    defer { serving.cancel() }
    let reply = try await Self.retrying { try await LocalSocket.call(Self.call, at: path) }
    #expect(reply == .value(Data("\"main\"".utf8)))
  }

  @Test func aCallWaitsForTheReplyItAccepts() async throws {
    let path = Self.path()
    defer { unlink(path.path) }
    let serving = Task {
      try await LocalSocket.serve(at: path) { _, reply in
        for number in 1...5 { try? await reply(.value(Data("\(number)".utf8))) }
      }
    }
    defer { serving.cancel() }
    let reply = try await Self.retrying {
      try await LocalSocket.call(Self.call, at: path) { $0 == .value(Data("3".utf8)) }
    }
    #expect(reply == .value(Data("3".utf8)))
  }

  @Test func theReplyIsKeptWhenTheAppHangsUpRightAfterIt() async throws {
    let path = Self.path()
    defer { unlink(path.path) }
    let serving = Task {
      try await LocalSocket.serve(at: path) { _, reply in try? await reply(.value(Data("1".utf8))) }
    }
    defer { serving.cancel() }
    _ = try await Self.retrying { try await LocalSocket.call(Self.call, at: path) }

    for _ in 0..<30 {
      #expect(try await LocalSocket.call(Self.call, at: path) == .value(Data("1".utf8)))
    }
  }

  @Test func aCallWithNoAppListeningSaysSo() async {
    await #expect(throws: LocalSocketError.notListening) {
      try await LocalSocket.call(Self.call, at: Self.path())
    }
  }

  private static func retrying(_ body: () async throws -> LocalReply) async throws -> LocalReply {
    for _ in 0..<50 {
      if let reply = try? await body() { return reply }
      try await Task.sleep(for: .milliseconds(20))
    }
    return try await body()
  }
}
