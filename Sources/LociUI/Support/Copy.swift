import Foundation

extension LocalizedStringResource {
  /// Interface text from Loci's string catalog, which holds every string in English and Chinese.
  static func loci(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
  }
}
