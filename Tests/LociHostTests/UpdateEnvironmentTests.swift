import Foundation
import LociMedia
import LociModel
import Testing

@testable import LociHost

struct UpdateEnvironmentTests {
  private static func system(_ variables: [String: String]) -> UpdateEnvironment {
    UpdateEnvironment.system(
      variables: variables, foreground: { AsyncStream { $0.finish() } }, busy: { AsyncStream { $0.finish() } },
      quit: {})
  }

  @Test func aTestCopyCanBePointedAtALocalFeed() {
    let local = "http://127.0.0.1:8765/latest.json"
    #expect(Self.system(["LOCI_UPDATE_FEED": local]).feed == URL(string: local))
  }

  @Test func withoutTheVariableTheCopyReadsThePublishedFeed() {
    #expect(Self.system([:]).feed == ReleaseFeed.loci)
    #expect(Self.system(["LOCI_UPDATE_FEED": ""]).feed == ReleaseFeed.loci)
  }
}
