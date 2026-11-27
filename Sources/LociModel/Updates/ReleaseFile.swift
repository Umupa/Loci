import Foundation

/// A file a release publishes besides its disk image, with where to download it and what it must hash to.
public struct ReleaseFile: Hashable, Codable, Sendable {
  /// The SHA-256 of the file, in lowercase hexadecimal.
  public let checksum: String
  public let size: Int64?
  /// The first place and then each mirror, tried in this order.
  public let places: [URL]

  public init(checksum: String, size: Int64? = nil, places: [URL]) {
    self.checksum = checksum
    self.size = size
    self.places = places
  }
}

/// What turns the copy of an earlier release into this one.
public struct ReleasePatch: Hashable, Codable, Sendable {
  public let from: ReleaseVersion
  public let file: ReleaseFile

  public init(from: ReleaseVersion, file: ReleaseFile) {
    self.from = from
    self.file = file
  }
}

/// One version's section of the changelog, one entry per change.
public struct ReleaseNotes: Hashable, Codable, Sendable {
  public let version: ReleaseVersion
  public let changes: [String]

  public init(version: ReleaseVersion, changes: [String]) {
    self.version = version
    self.changes = changes
  }

  /// Reads a changelog section: each `- ` line starts a change, and the lines under it carry it on.
  public init(version: ReleaseVersion, section: String) {
    var changes: [String] = []
    for line in section.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("- ") {
        changes.append(String(trimmed.dropFirst(2)))
      } else if !trimmed.isEmpty, let last = changes.indices.last {
        changes[last] += " " + trimmed
      } else if !trimmed.isEmpty {
        changes.append(trimmed)
      }
    }
    self.init(version: version, changes: changes)
  }
}
