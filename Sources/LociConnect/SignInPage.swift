import Foundation

/// What came of a sign-in, as the browser that came back is told.
public enum SignInOutcome: Hashable, Sendable {
  case connected
  /// The person refused on the service's page.
  case declined
  case failed
}

/// The page the browser shows once it is back from a sign-in: Loci's icon over one line saying what came of it,
/// in the language the browser asks for first, on paper in light and dark. Everything is in the page, so it
/// shows the same without a network.
struct SignInPage {
  let service: String
  let outcome: SignInOutcome
  let language: Language

  enum Language: Hashable {
    case chinese, english

    /// The first of Chinese or English in an `Accept-Language` header, by weight; English when neither is asked.
    init(acceptLanguage: String?) {
      let ranges = (acceptLanguage ?? "").split(separator: ",").enumerated().compactMap {
        index, part -> (tag: String, weight: Double, index: Int)? in
        let fields = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let tag = fields.first?.lowercased(), !tag.isEmpty else { return nil }
        let weight = fields.dropFirst().first { $0.hasPrefix("q=") }.flatMap { Double($0.dropFirst(2)) } ?? 1
        return (tag, weight, index)
      }
      let first = ranges.sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.index < $1.index }
        .first { $0.tag.hasPrefix("zh") || $0.tag.hasPrefix("en") }
      self = first?.tag.hasPrefix("zh") == true ? .chinese : .english
    }
  }

  var line: String {
    switch (language, outcome) {
    case (.chinese, .connected): "已连上 \(service)"
    case (.chinese, .declined): "没有授权连接 \(service)"
    case (.chinese, .failed): "没能连上 \(service)"
    case (.english, .connected): "Connected to \(service)"
    case (.english, .declined): "Access to \(service) wasn’t granted"
    case (.english, .failed): "Couldn’t connect to \(service)"
    }
  }

  var html: String {
    let icon = Self.icon.map { "<img src=\"data:image/png;base64,\($0)\" width=\"80\" height=\"80\" alt=\"\">" } ?? ""
    return """
      <!doctype html>
      <html lang="\(language == .chinese ? "zh-Hans" : "en")">
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="color-scheme" content="light dark">
      <title>Loci</title>
      <style>
      :root { --paper: #F6F1E7; --ink: #2B2621; }
      @media (prefers-color-scheme: dark) { :root { --paper: #302B25; --ink: #F2E8D7; } }
      body { margin: 0; min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 20px;
        background: var(--paper); color: var(--ink);
        font: 500 17px/1.4 -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; }
      img { display: block; }
      p { margin: 0; padding: 0 24px; text-align: center; }
      </style>
      \(icon)
      <p>\(Self.escaped(line))</p>
      <script>setTimeout(function () { window.close(); }, 1500);</script>
      </html>
      """
  }

  private static let icon: String? = Bundle.module.url(
    forResource: "loci", withExtension: "png", subdirectory: "Resources"
  )
  .flatMap { try? Data(contentsOf: $0) }?.base64EncodedString()

  private static func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
