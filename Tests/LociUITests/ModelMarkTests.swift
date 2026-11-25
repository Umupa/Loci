import LociModel
import Testing

@testable import LociUI

@MainActor
struct ModelMarkTests {
  @Test(arguments: ModelPreset.allCases.filter { $0 != .custom })
  func everyBuiltInProviderHasArtworkInBothAppearances(preset: ModelPreset) {
    #expect(MarkArt.model(preset, in: .light)?.isValid == true)
    #expect(MarkArt.model(preset, in: .dark)?.isValid == true)
  }
}
