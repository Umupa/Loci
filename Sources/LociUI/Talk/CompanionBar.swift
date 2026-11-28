import LociModel
import SwiftUI

/// What stays put over the companion's pages as they slide: who the companion is in the top-left corner, and
/// the project bar centred between the same room kept clear on either side, with a warm light under it while a
/// project is being made.
struct CompanionBar: View {
  let bar: ProjectBar
  let home: Home
  /// How wide the page is, for how much of it the bar may take.
  let pageWidth: CGFloat
  let newSeal: NewSeal?
  let suggested: [Project.ID: String]
  let stamps: [Home: Int]
  let travel: PageTravel
  let actions: ProjectBarActions
  @Environment(\.sidebarShown) private var sidebarShown
  @State private var badgeWidth: CGFloat = 0
  @State private var building = false

  var body: some View {
    let badgeLeading = CompanionBadge.leading(sidebarShown: sidebarShown)
    let clearance = max(Size.projectBarClearance, badgeLeading + badgeWidth + Spacing.s)
    let barBudget = pageWidth > 0 ? max(240, pageWidth - clearance * 2) : Size.projectBarWidest
    ZStack(alignment: .top) {
      BarClearance(leading: clearance, trailing: clearance) {
        ProjectBarView(
          bar: bar, home: travel.heading.home ?? home, maxWidth: barBudget, newSeal: newSeal, suggested: suggested,
          stamps: stamps, travel: travel, actions: actions
        )
        .background { WarmLight(on: building) }
      }
      .padding(.top, 11)
      .onPreferenceChange(Building.self) { building = $0 }
      CompanionBadge()
        .onGeometryChange(for: CGFloat.self) {
          $0.size.width
        } action: {
          badgeWidth = $0
        }
        .frame(maxWidth: Self.badgeWidest, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, badgeLeading)
        .padding(.top, Spacing.xs)
    }
  }

  /// The most of the corner the companion's name and line take before they are cut short.
  private static let badgeWidest: CGFloat = 220
}
