import SwiftUI

/// What every page of the window shares: covers, pictures, deletions and pictures in flight.
struct WindowShared: ViewModifier {
  let covers: Covers
  let deletions: Deletions
  let linkPreviews: LinkPreviews
  let pictures: WebPictures
  let flights: Flights
  let followCardLink: URL?

  func body(content: Content) -> some View {
    content
      .environment(\.covers, covers)
      .environment(\.deletions, deletions)
      .environment(\.linkPreviews, linkPreviews)
      .environment(\.webPictures, pictures)
      .environment(\.flights, flights)
      .environment(\.followCardLink, followCardLink)
  }
}
