import Foundation

extension URL {
  /// An http or https link with a host: something to open in a browser or fetch.
  public var isWebLink: Bool {
    ["http", "https"].contains(scheme?.lowercased()) && host?.isEmpty == false
  }
}
