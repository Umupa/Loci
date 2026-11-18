import SwiftUI

extension EnvironmentValues {
  /// Whether the Mac behind the window can take changes now: not while a remote Mac is offline or being dialed
  /// again. What it already sent stays readable either way.
  var changesAllowed: Bool { machineChoice?.offline == nil }
}

extension View {
  /// Marks a control that changes the data of the Mac behind the window, so it is off while that Mac cannot take
  /// changes. `applies` is false for the times the same control only goes somewhere, such as a fix that opens a
  /// page instead of downloading.
  func changesData(_ applies: Bool = true) -> some View {
    modifier(ChangesData(applies: applies))
  }
}

private struct ChangesData: ViewModifier {
  @Environment(\.changesAllowed) private var allowed
  let applies: Bool

  func body(content: Content) -> some View {
    content.disabled(applies && !allowed)
  }
}
