import LociModel
import Testing

@testable import LociHost

/// P-S6: what the composer sends to ask for a new panel is what Loci's rules recognize, in both languages.
struct NewPanelRequestTests {
  @Test func theRulesRecognizeTheRequestInBothLanguages() throws {
    let rules = try Prompts.bundled().rules
    #expect(rules.contains("「\(NewPanelRequest.chinese)」"))
    #expect(rules.contains("\"\(NewPanelRequest.english)\""))
  }
}

/// P-S8: a refresh that cannot get what the panel follows leaves the panel as it was.
struct PanelRefreshPromptTests {
  static let unreachable = "If you cannot get what it follows"

  @Test func aRefreshIsToldNotToSaveWhenItCannotGetWhatThePanelFollows() throws {
    let prompts = try Prompts.bundled()
    let refresh = try prompts.panel(PanelScenarioTests.radar, hidden: [:])

    #expect(refresh.contains("\(Self.unreachable), do not save anything"))
    #expect(ToolGuide.topic("panels")?.contains("\(Self.unreachable) in a refresh, save nothing") == true)
  }
}
