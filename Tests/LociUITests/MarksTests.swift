import LociModel
import Testing

@testable import LociUI

@MainActor
struct MarksTests {
  @Test func everyMentorSignIsDrawn() {
    for mark in Mentor.Mark.allCases { #expect(MarkArt.mentor(mark) != nil, "\(mark)") }
  }

  @Test func everyCourseSignIsDrawn() {
    for mark in Mentor.CourseMark.allCases { #expect(MarkArt.course(mark) != nil, "\(mark)") }
  }

  @Test func everyAgentHasItsLogo() {
    for provider in Mentor.Provider.allCases { #expect(MarkArt.agent(provider) != nil, "\(provider)") }
  }
}
