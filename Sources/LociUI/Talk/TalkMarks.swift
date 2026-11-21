import SwiftUI

/// Where a new day or a new sitting begins: a hairline across the column, and under it `今天 09:12`.
struct DayDivider: View {
  let label: Text

  var body: some View {
    label
      .font(.system(size: 12))
      .foregroundStyle(Palette.inkFaint)
      .frame(maxWidth: .infinity)
      .padding(.top, 14)
      .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
      .padding(.top, 22)
      .padding(.bottom, 12)
  }
}
