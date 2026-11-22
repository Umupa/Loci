import AppKit
import SwiftUI

/// Loci's face: the picture the person chose, or the one drawn for it.
enum LociFace: Equatable {
  case drawn
  case picture(NSImage)

  /// The app's default portrait, composed for a circle.
  @MainActor static let drawing: NSImage? = Bundle.module.url(forResource: "loci-face", withExtension: "png")
    .flatMap(NSImage.init(contentsOf:))

  @MainActor var image: NSImage? {
    switch self {
    case .drawn: Self.drawing
    case .picture(let picture): picture
    }
  }
}

extension EnvironmentValues {
  /// The face every avatar shows, so changing it changes them all at once.
  @Entry var lociFace: LociFace = .drawn
}
