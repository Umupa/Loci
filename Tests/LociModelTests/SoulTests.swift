import Testing

@testable import LociModel

struct SoulTests {
  static let file = """
    # Soul

    You are Loci.

    ## Evolved Traits
    - 2026-11-03 越来越受不了标题党。
    - Found that drawing beats typing.
    a stray line
    - 2026-11-17 开始在意对面那个人是不是又熬夜了。
    """

  @Test func theCoreIsEverythingAboveTheTraits() {
    #expect(Soul(parsing: Self.file).core == "# Soul\n\nYou are Loci.")
  }

  @Test func traitsComeNewestFirstWithOrWithoutADay() {
    let traits = Soul(parsing: Self.file).traits

    #expect(
      traits == [
        .entry(Trait(day: Day("2026-11-17"), text: "开始在意对面那个人是不是又熬夜了。")),
        .text("a stray line"),
        .entry(Trait(day: nil, text: "Found that drawing beats typing.")),
        .entry(Trait(day: Day("2026-11-03"), text: "越来越受不了标题党。")),
      ])
  }

  @Test func withoutATraitsHeadingTheWholeFileIsTheCore() {
    let soul = Soul(parsing: "You are Loci.\n- a list in the core\n")

    #expect(soul.core == "You are Loci.\n- a list in the core")
    #expect(soul.traits.isEmpty)
  }

  @Test func theHeadingIsFoundWhateverItsCaseAndSpacing() {
    #expect(Soul(parsing: "core\n  ## evolved traits  \n- one").traits == [.entry(Trait(day: nil, text: "one"))])
  }

  @Test func rewritingTheCoreLeavesTheTraitsUntouched() throws {
    let rewritten = try Soul.rewriting(Self.file, core: "  You are someone else.\n")

    #expect(rewritten.hasPrefix("You are someone else.\n\n## Evolved Traits\n- 2026-11-03 越来越受不了标题党。"))
    #expect(rewritten.hasSuffix("- 2026-11-17 开始在意对面那个人是不是又熬夜了。"))
    #expect(Soul(parsing: rewritten).traits == Soul(parsing: Self.file).traits)
  }

  @Test func rewritingAFileWithoutTraitsStartsAnEmptyList() throws {
    let rewritten = try Soul.rewriting("old", core: "new")

    #expect(rewritten == "new\n\n## Evolved Traits\n")
    #expect(Soul(parsing: rewritten).core == "new")
  }

  @Test func aCoreThatIsBlankOrHoldsTheTraitsHeadingIsRefused() {
    #expect(throws: ModelError.self) { try Soul.rewriting(Self.file, core: " \n") }
    #expect(throws: ModelError.self) { try Soul.rewriting(Self.file, core: "x\n## Evolved Traits\n- y") }
  }
}
