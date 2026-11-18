import Foundation
import LociModel
import SwiftUI

extension SpeechModel {
  /// The model's name as Whisper's makers give it; the compressed Turbo is named in the reader's language.
  var title: Text {
    switch self {
    case .tiny: Text(verbatim: "Tiny")
    case .base: Text(verbatim: "Base")
    case .small: Text(verbatim: "Small")
    case .medium: Text(verbatim: "Medium")
    case .largeV3TurboQuantized: Text(.loci("media.turboCompressed"))
    case .largeV3Turbo: Text(verbatim: "Large v3 Turbo")
    case .largeV3: Text(verbatim: "Large v3")
    }
  }

  /// `77.7 MB`, `1.53 GB`, in decimal units as the download reports them.
  var sizeText: String {
    Self.bytes(size)
  }

  static func bytes(_ count: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .decimal
    return formatter.string(fromByteCount: count)
  }
}
