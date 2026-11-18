import SwiftUI

/// Whether the conversation keeps its newest line in view. It does until the person scrolls up, and again
/// once they scroll back to the end, ask something, or jump to the latest.
struct Following: Equatable {
  private(set) var isOn = true

  /// How near the end still counts as at the end.
  static let slack: CGFloat = 48

  /// The person scrolled, and stopped `distance` points above the end.
  mutating func scrolled(to distance: CGFloat) {
    isOn = distance <= Self.slack
  }

  mutating func asked() {
    isOn = true
  }

  mutating func returned() {
    isOn = true
  }

  /// The way back to the latest shows while the conversation is not following.
  var offersLatest: Bool { !isOn }

  /// How far the bottom of what shows is above the end of the conversation.
  static func distanceFromEnd(_ geometry: ScrollGeometry) -> CGFloat {
    geometry.contentSize.height + geometry.contentInsets.bottom - geometry.contentOffset.y
      - geometry.containerSize.height
  }
}

/// The round button over the composer that goes back to the newest message: an arrow, or while the mentor
/// is still answering, dots that pulse.
struct LatestButton: View {
  let busy: Bool
  let action: () -> Void

  static let size: CGFloat = 30

  var body: some View {
    Button(action: action) {
      Group {
        if busy {
          Image(systemName: Symbols.more).symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
          Image(systemName: Symbols.latest)
        }
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Palette.inkMuted)
      .frame(width: Self.size, height: Self.size)
      .background(Circle().fill(Palette.surface).shadow(color: .black.opacity(0.1), radius: 6, y: 3))
      .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
      .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(Text(.loci("conversation.latest")))
  }
}
