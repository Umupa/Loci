import Foundation
import SwiftUI

/// Files the Finder asked Loci to open, such as a `.epub` double-clicked, waiting for a window to take them.
@MainActor
@Observable
public final class OpenedFiles {
  public private(set) var waiting: [URL] = []

  public init() {}

  public func open(_ files: [URL]) {
    waiting += files.filter(\.isFileURL)
  }

  /// Hands over every file waiting, once.
  func take() -> [URL] {
    defer { waiting = [] }
    return waiting
  }
}

extension EnvironmentValues {
  @Entry var openedFiles: OpenedFiles?
}

extension View {
  /// Lets the windows inside take the files the Finder opens with Loci.
  public func openingFiles(_ files: OpenedFiles) -> some View {
    environment(\.openedFiles, files)
  }
}
