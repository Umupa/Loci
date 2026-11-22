/// A program Loci downloads or finds on this Mac.
public enum Component: String, CaseIterable, Codable, Hashable, Sendable {
  /// Finds and fetches video and audio from a link.
  case ytDlp
  /// Remuxes, extracts audio tracks.
  case ffmpeg
  /// Lets yt-dlp run the scripts some sites need.
  case quickJS
  case bundledPi
}

/// Where a component was found, and which version.
public struct ComponentStatus: Hashable, Codable, Sendable {
  public let component: Component
  public let installation: Installation

  public init(component: Component, installation: Installation) {
    self.component = component
    self.installation = installation
  }

  public enum Installation: Hashable, Codable, Sendable {
    /// Already on this Mac, such as from Homebrew; Loci uses it and leaves it alone.
    case system(path: String, version: String?)
    /// Downloaded into Loci's own folder, and updated by Loci.
    case managed(version: String?)
    case missing
  }
}
