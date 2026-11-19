import LociModel
import Testing

struct ReleaseVersionTests {
  @Test func readsATagWithOrWithoutTheLeadingV() {
    #expect(ReleaseVersion("v1.2.0") == ReleaseVersion("1.2.0"))
    #expect(ReleaseVersion("1.0.0-alpha.1")?.description == "1.0.0-alpha.1")
  }

  @Test(arguments: ["", "1.2", "1.2.x", "Loci 1.2.0", "1.2.0 "])
  func refusesAnythingElse(text: String) {
    #expect(ReleaseVersion(text) == nil)
  }

  @Test func ordersByNumberNotByText() throws {
    let ordered = ["1.0.0-alpha.1", "1.0.0-alpha.2", "1.0.0-alpha.10", "1.0.0", "1.1.0", "1.1.1", "1.10.0", "2.0.0"]
    let versions = try ordered.map { try #require(ReleaseVersion($0)) }
    #expect(versions.shuffled().sorted() == versions)
  }
}
