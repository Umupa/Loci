import SwiftUI

/// What stands where text would be typed while the Mac behind the window cannot take changes.
struct OfflineLine: View {
  let name: String
  /// A hairline above, where the line closes off a panel.
  var ruled = true

  var body: some View {
    Text(.loci("remote.offline \(name)"))
      .font(Typography.body)
      .foregroundStyle(Palette.inkFaint)
      .frame(maxWidth: .infinity)
      .frame(height: Size.offlineLine)
      .overlay(alignment: .top) {
        if ruled { Rectangle().fill(Palette.line).frame(height: Size.hairline) }
      }
  }
}

extension View {
  /// Shows an `OfflineLine` instead of this field while the Mac behind the window is offline.
  func offlineLineInstead(ruled: Bool = true) -> some View {
    modifier(OfflineLineInstead(ruled: ruled))
  }
}

private struct OfflineLineInstead: ViewModifier {
  @Environment(\.machineChoice) private var choice
  let ruled: Bool

  func body(content: Content) -> some View {
    if let offline = choice?.offline {
      OfflineLine(name: offline.name, ruled: ruled)
    } else {
      content
    }
  }
}
