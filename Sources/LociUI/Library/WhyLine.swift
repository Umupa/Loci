import LociModel
import SwiftUI

/// Under an item's title: why the reader took it in, in their words, in the serif's italic.
struct WhyLine: View {
  let item: Item
  var alignment: TextAlignment = .leading

  var body: some View {
    if let why = item.why {
      Text(verbatim: why)
        .font(.system(size: 14.5, design: .serif).italic())
        .foregroundStyle(Palette.inkMuted)
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
