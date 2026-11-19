import LociModel
import SwiftUI
import Testing

@testable import LociUI

@MainActor
struct MarksTests {
  @Test(arguments: [ColorScheme.light, .dark])
  func everyAgentHasItsLogoInBothAppearances(scheme: ColorScheme) {
    for provider in Provider.allCases { #expect(MarkArt.agent(provider, in: scheme) != nil, "\(provider)") }
  }

  @Test(arguments: [Component.ytDlp, .ffmpeg])
  func theComponentsWithPublishedIconsShipThoseIcons(component: Component) {
    #expect(MarkArt.component(component) != nil)
  }
}
