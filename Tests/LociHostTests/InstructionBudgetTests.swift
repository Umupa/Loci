import Foundation
import LociModel
import Testing

@testable import LociHost

/// ME-S6, ME-S9: every session's instructions stay short, say what memory is for, and leave the formats to
/// `loci help`.
struct InstructionBudgetTests {
  /// A profile as long as one the review keeps.
  static let profile =
    "# User\n\n"
    + String(repeating: "- 2026-11-01 后端工程师，在学沙箱和调度，想做 AI Infra。\n", count: 80)
    .prefix(2_000)

  @Test func agentsFileStaysUnderTenThousandCharacters() throws {
    let prompts = try Prompts.bundled()

    let instructions = prompts.instructions(soul: prompts.soul, profile: String(Self.profile), name: "小满")

    #expect(instructions.count <= 10_000, "AGENTS.md is \(instructions.count) characters")
  }

  @Test func aProjectsAgentsFileStaysUnderTenThousandCharactersToo() throws {
    let prompts = try Prompts.bundled()
    var entropy = SeededGenerator(seed: 1)
    let project = Project(
      id: EntityID(at: Date(timeIntervalSince1970: 1_763_337_600), entropy: &entropy), name: "AI Infra 面试",
      summary: "准备 AI Infra 平台方向的面试，每周两次模拟", createdAt: Timestamp(millisecondsSince1970: 0))

    let instructions = prompts.instructions(
      soul: prompts.soul, profile: String(Self.profile), name: "小满", project: project)

    #expect(instructions.count <= 10_000, "a project's AGENTS.md is \(instructions.count) characters")
  }

  @Test func theChatsAgentsFileSaysItWorksInTheAgentFolder() throws {
    let prompts = try Prompts.bundled()

    let instructions = prompts.instructions(soul: prompts.soul, profile: "# User\n", name: "")

    #expect(instructions.contains("You work in `agent/`. The person's library is in `../library/`"))
    #expect(!instructions.contains("{{") && !instructions.contains("# This project"))
  }

  @Test func theRulesSayWhatMemoryIsForAndEveryTopicTheyPointToIsInLociHelp() throws {
    let rules = try Prompts.bundled().rules

    #expect(rules.contains("Remember what cannot be looked up again"))
    #expect(rules.contains("Do not copy what the library, a connector or a panel already holds"))
    #expect(!rules.contains("```md"))
    for topic in ["memory", "notes", "feelings", "panels", "schedules", "connectors", "courses", "locators"] {
      #expect(ToolGuide.topic(topic) != nil, "loci help \(topic)")
      #expect(rules.contains(topic), "the rules do not point to \(topic)")
    }
    #expect(rules.contains("```loci-replies") && rules.contains("loci-doc"))
  }

  @Test func theSkillHoldsTheOverviewAndEveryTopic() {
    for topic in ToolGuide.topics { #expect(ToolGuide.skill.contains(topic.text)) }
    #expect(ToolGuide.skill.contains(ToolGuide.text))
  }
}
