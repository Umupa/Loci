import Foundation
import Testing

@testable import LociConnect

/// CN-S1: the browser comes back to a port on 127.0.0.1 that only this connection listens at.
@Suite(.timeLimit(.minutes(1)))
struct LoopbackTests {
  private func get(_ url: URL) async throws -> String {
    let (data, _) = try await URLSession(configuration: .ephemeral).data(from: url)
    return String(decoding: data, as: UTF8.self)
  }

  @Test func theReceiverListensOn127001AndHandsBackTheCallback() async throws {
    let wait = try await LoopbackReceiver().open()
    #expect(wait.redirect.host() == "127.0.0.1" && wait.redirect.path() == "/callback")
    let back = try #require(URL(string: wait.redirect.absoluteString + "?code=abc&state=xyz"))

    let page = try await get(back)
    let callback = try await wait.callback()
    await wait.close()

    #expect(page.contains("Loci"))
    #expect(callback.query() == "code=abc&state=xyz")
  }

  @Test func aRequestWithoutCodeOrErrorIsAnsweredAndIgnored() async throws {
    let wait = try await LoopbackReceiver().open()
    let favicon = try #require(URL(string: "http://127.0.0.1:\(wait.redirect.port ?? 0)/favicon.ico"))
    let back = try #require(URL(string: wait.redirect.absoluteString + "?error=access_denied"))

    _ = try await get(favicon)
    _ = try await get(back)
    let callback = try await wait.callback()
    await wait.close()

    #expect(callback.query() == "error=access_denied")
  }
}
