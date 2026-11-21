import Foundation

/// How a message asking Loci for a new panel begins, as the composer sends it and Loci's rules recognize it.
public enum NewPanelRequest {
  public static let chinese = "创建一个新面板"
  public static let english = "Create a new panel"

  /// The request in the language of `locale`: Chinese for Chinese, English otherwise.
  public static func message(_ text: String, locale: Locale) -> String {
    locale.language.languageCode == .chinese ? "\(chinese)：\(text)" : "\(english): \(text)"
  }
}
