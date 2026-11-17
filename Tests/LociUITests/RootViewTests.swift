import Foundation
import Testing

@testable import LociUI

@MainActor
struct RootViewTests {
  @Test(arguments: Snapshot.Appearance.allCases)
  func rendersInBothAppearances(appearance: Snapshot.Appearance) throws {
    let file = try Snapshot.render(
      RootView(), named: "root", size: CGSize(width: 960, height: 600), appearance: appearance)

    let bytes = try Data(contentsOf: file).count
    #expect(bytes > 1_000)
  }
}
