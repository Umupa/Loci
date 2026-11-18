import Testing

@testable import LociModel

struct ContentRefTests {
  @Test func aLocatorKnowsWhichContentItPointsInto() throws {
    let locator = Locator.item(Fixture.item, .quote(try TextQuote("x")))

    #expect(locator.content == .item(Fixture.item))
    #expect(locator.item == Fixture.item)
  }
}
