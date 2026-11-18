import AppKit
import SwiftUI

/// Loci's face: the picture the person chose, or the one drawn for it.
enum LociFace: Equatable {
  case drawn
  case picture(NSImage)

  /// The drawing shipped with the app, a vector that stays sharp at every size.
  @MainActor static let drawing: NSImage? = Bundle.module.url(forResource: "loci-face", withExtension: "svg")
    .flatMap(NSImage.init(contentsOf:))

  /// The square of the drawing that holds the face, for small avatars, in the drawing's own units.
  static let faceCrop = CGRect(x: 26, y: 22, width: 68, height: 68)
  static let drawingSide: CGFloat = 120
}

extension EnvironmentValues {
  /// The face every avatar shows, so changing it changes them all at once.
  @Entry var lociFace: LociFace = .drawn
}
