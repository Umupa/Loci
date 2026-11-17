import LociModel
import Testing

struct MentorMarkTests {
  static let id = EntityID("0199a5c1-7a2b-7c3d-8e4f-0123456789ab")

  @Test func aMentorWearsTheSignItsAvatarNames() throws {
    let mentor = try Mentor(id: EntityID(), name: "调度", avatar: "lyra", color: MentorColor.palette[0], provider: .pi)

    #expect(mentor.mark == .lyra)
  }

  @Test func aMentorFromAnEarlierVersionKeepsTheSameSignEveryTime() throws {
    let id = try #require(Self.id)
    let first = try Mentor(id: id, name: "调度", avatar: "nimbus", color: MentorColor.palette[0], provider: .pi)
    let again = try Mentor(id: id, name: "改名", avatar: "nimbus", color: MentorColor.palette[1], provider: .codex)

    #expect(first.mark == again.mark)
    #expect(first.avatar == "nimbus")
  }

  @Test func aCourseKeepsTheSameSignEveryTime() throws {
    let id = try #require(Self.id)
    let first = try Mentor(id: id, name: "调度", avatar: "ember", color: MentorColor.palette[0], provider: .pi)
    let renamed = try Mentor(id: id, name: "改名", avatar: "luna", color: MentorColor.palette[1], provider: .pi)

    #expect(first.courseMark == renamed.courseMark)
  }

  @Test func newMentorsHaveDistinctColoursToChooseFrom() {
    #expect(Set(MentorColor.palette).count == MentorColor.palette.count)
  }

  @Test func aColourFromThePaletteIsShownAsItIs() {
    for color in MentorColor.palette { #expect(color.nearestInPalette == color) }
  }

  @Test(arguments: [
    ("#459bf7", "#4d6a8c"), ("#ea603e", "#b45a3c"), ("#f4c025", "#b07a2a"), ("#e25a9e", "#7d4868"),
    ("#37beb3", "#3c7670"), ("#6e63e9", "#67598c"),
  ])
  func aColourFromAnEarlierVersionIsShownAsTheWarmColourOfTheNearestHue(old: String, shown: String) throws {
    let color = try #require(MentorColor(old))

    #expect(color.nearestInPalette.description == shown)
  }
}
