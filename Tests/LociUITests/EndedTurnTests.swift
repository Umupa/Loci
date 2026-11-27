import Testing

@testable import LociUI

struct EndedTurnTests {
  @Test func aFailedTurnSaysTheLastLineTheAgentGaveAsItsReason() {
    let traceback = """
      Traceback (most recent call last):
        File "client.py", line 12, in connect
      ImportError: Using SOCKS proxy, but the 'socksio' package is not installed.

      """
    #expect(
      EndedTurn.cause(in: traceback) == "ImportError: Using SOCKS proxy, but the 'socksio' package is not installed.")
  }

  @Test func aFailureWithoutWordsHasNoReason() {
    #expect(EndedTurn.cause(in: " \n\n") == nil)
  }

  @Test func aLongReasonIsCutToASentence() throws {
    let cause = try #require(EndedTurn.cause(in: String(repeating: "x", count: 500)))
    #expect(cause.count == 240)
    #expect(cause.hasSuffix("…"))
  }
}
