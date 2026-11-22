import SwiftUI

/// The courses page behind the builder: the field for what to learn over the gallery of books, or over an empty
/// book when there are none yet.
struct CourseShelf: View {
  let books: [CourseBook]
  @Binding var wish: String
  var hidden: CourseBook.ID?
  var pointed: CourseBook.ID?
  var bumped: Bump?
  let start: (String) -> Void
  let open: (CourseBook) -> Void
  let delete: (CourseBook) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        WishField(text: $wish, send: start)
          .changesData()
          .padding(.bottom, 34)
        if books.isEmpty {
          EmptyShelf()
        } else {
          CourseGallery(
            books: books, hidden: hidden, pointed: pointed, bumped: bumped, open: open, delete: delete)
        }
      }
      .frame(maxWidth: 968)
      .padding(.horizontal, 40)
      .padding(.top, 22)
      .padding(.bottom, 80)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.automatic)
    .background(Palette.canvas)
  }
}
