import Foundation
import SwiftUI

extension LocalizedStringResource {
  /// Interface text from Loci's string catalog, which holds every string in English and Chinese.
  static func loci(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
  }
}

extension Text {
  /// Pieces of text read as one line, each keeping its own font and color.
  init(joining parts: Text...) {
    var whole = Text(verbatim: "")
    for part in parts {
      let joined: LocalizedStringKey = "\(whole)\(part)"
      whole = Text(joined)
    }
    self = whole
  }
}
