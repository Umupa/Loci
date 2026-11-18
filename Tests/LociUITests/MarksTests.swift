import LociModel
import Testing

@testable import LociUI

@MainActor
struct MarksTests {
  @Test func everyAgentHasItsLogo() {
    for provider in Provider.allCases { #expect(MarkArt.agent(provider) != nil, "\(provider)") }
  }
}
