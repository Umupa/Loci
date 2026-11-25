import CryptoKit
import Foundation
import LociModel
import Testing

@testable import LociMedia

/// DS-S4: a source's script runs where it reaches no network, no files and no other source, and is stopped
/// when it runs too long.
@MainActor
struct ParseSandboxTests {
  static let now = Timestamp(millisecondsSince1970: 1_764_000_000_000)

  static func parse(_ script: String, _ responses: [SourceResponse] = [], timeout: Duration = .seconds(5))
    async throws(SourceProblems) -> JSONValue
  {
    try await ParseSandbox.run(script, .parse(responses: responses), now: now, timeout: timeout)
  }

  static func failure(_ script: String, timeout: Duration = .seconds(5)) async -> [String] {
    do throws(SourceProblems) {
      _ = try await parse(script, timeout: timeout)
      return []
    } catch {
      return error.all.map(\.description)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func parseTurnsResponsesIntoRecords() async throws {
    let script = """
      function parse(responses, now) {
        const [, price] = responses[0].text.split("~");
        return { records: { "513100": { price: Number(price), at: now.getTime() } }, state: { seen: 1 } };
      }
      """

    let json = try await Self.parse(
      script, [SourceResponse(url: URL(string: "https://qt.gtimg.cn/q=sh513100")!, status: 200, text: "v~1.873")])

    #expect(
      json
        == JSONValue(
          parsing: #"{ "records": { "513100": { "price": 1.873, "at": 1764000000000 } }, "state": { "seen": 1 } }"#))
  }

  @Test(.timeLimit(.minutes(1)))
  func requestsAreGivenTheStateParseLeft() async throws {
    let json = try await ParseSandbox.run(
      "async function requests(state) { return [`https://a.example/after/${state.last}`]; }",
      .requests(state: .object(["last": .integer(7)])), now: Self.now, timeout: .seconds(5))

    #expect(json == .array([.string("https://a.example/after/7")]))
  }

  @Test(.timeLimit(.minutes(1)))
  func theScriptReachesNoNetworkAndNoStorage() async {
    for reach in [
      "fetch('https://example.com')", "new XMLHttpRequest()", "new WebSocket('wss://example.com')",
      "localStorage.setItem('a', 1)", "indexedDB.open('a')",
    ] {
      #expect(await Self.failure("function parse() { \(reach); return { records: {} }; }") != [], "\(reach)")
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func oneRunSeesNothingTheLastOneLeft() async throws {
    _ = try await Self.parse("function parse() { globalThis.leftover = 1; return { records: {} }; }")

    let json = try await Self.parse("function parse() { return { records: {}, state: typeof leftover }; }")

    #expect(json["state"] == .string("undefined"))
  }

  @Test(.timeLimit(.minutes(1)))
  func aScriptThatRunsTooLongIsStoppedAndTheNextRunsAsUsual() async throws {
    let started = ContinuousClock.now

    let problems = await Self.failure("function parse() { while (true) {} }", timeout: .milliseconds(500))

    #expect(problems == ["script: ran longer than 0.5 seconds and was stopped"])
    #expect(ContinuousClock.now - started < .seconds(5))
    let json = try await Self.parse("function parse() { return { records: {} }; }")
    #expect(json == JSONValue(parsing: #"{ "records": {} }"#))
  }

  @Test(.timeLimit(.minutes(1)))
  func aScriptThatThrowsSaysWhatAndWhere() async {
    let problems = await Self.failure("function parse() {\n  return undefinedThing.x;\n}")

    #expect(problems.count == 1)
    #expect(problems.first?.contains("undefinedThing") == true)
  }

  @Test(.timeLimit(.minutes(1)))
  func md5AndSha1AreTheAppsAndTimeIsTheGivenNow() async throws {
    let texts = ["", "abc", "签名 key=513100&t=1764000000", String(repeating: "x", count: 200)]
    let script = """
      function parse(responses, now) {
        const texts = \(JSONValue.array(texts.map(JSONValue.string)).text);
        return { records: {}, state: { md5: texts.map(md5), sha1: texts.map(sha1), now: Date.now(), date: new Date().getTime() } };
      }
      """

    let state = try await Self.parse(script)["state"]

    let hex = { (digest: any Sequence<UInt8>) in digest.map { String(format: "%02x", $0) }.joined() }
    #expect(state?["md5"] == .array(texts.map { .string(hex(Insecure.MD5.hash(data: Data($0.utf8)))) }))
    #expect(state?["sha1"] == .array(texts.map { .string(hex(Insecure.SHA1.hash(data: Data($0.utf8)))) }))
    #expect(state?["now"] == .integer(Self.now.millisecondsSince1970))
    #expect(state?["date"] == .integer(Self.now.millisecondsSince1970))
  }
}
