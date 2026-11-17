import AppKit
import SwiftUI

/// Light, dark, or following the system: a choice for this Mac's windows, kept with its preferences.
enum AppearanceChoice: String, CaseIterable {
  case auto, light, dark

  static let key = "appearance"

  var appearance: NSAppearance? {
    switch self {
    case .auto: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }

  var name: LocalizedStringResource {
    switch self {
    case .auto: .loci("appearance.auto")
    case .light: .loci("appearance.light")
    case .dark: .loci("appearance.dark")
    }
  }
}

extension View {
  /// Applies the appearance chosen in the settings to the whole app, now and whenever it changes.
  public func lociAppearance() -> some View {
    modifier(AppliedAppearance())
  }
}

private struct AppliedAppearance: ViewModifier {
  @AppStorage(AppearanceChoice.key) private var choice = AppearanceChoice.auto

  func body(content: Content) -> some View {
    content
      .onAppear { NSApp?.appearance = choice.appearance }
      .onChange(of: choice) { NSApp?.appearance = choice.appearance }
  }
}
