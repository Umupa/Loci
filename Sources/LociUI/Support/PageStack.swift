import SwiftUI

/// Pages opened over a place, each able to open the next.
///
/// The opener is handed to the place and to every page itself: values set on a `NavigationStack` do not
/// reach the pages it pushes, so a page would otherwise get the opener that does nothing.
struct PageStack<Place: View, Destination: View>: View {
  @Binding var pages: [Page]
  let place: Place
  let destination: (Page) -> Destination

  init(
    pages: Binding<[Page]>, @ViewBuilder place: () -> Place, @ViewBuilder destination: @escaping (Page) -> Destination
  ) {
    _pages = pages
    self.place = place()
    self.destination = destination
  }

  var body: some View {
    NavigationStack(path: $pages) {
      place
        .environment(\.openPage, opener)
        .navigationDestination(for: Page.self) { destination($0).environment(\.openPage, opener) }
    }
  }

  private var opener: OpenPage {
    let pages = $pages
    return OpenPage { pages.wrappedValue.append($0) }
  }
}
