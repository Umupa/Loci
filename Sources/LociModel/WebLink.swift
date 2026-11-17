import Foundation

extension URL {
  var isWebLink: Bool {
    ["http", "https"].contains(scheme?.lowercased()) && host?.isEmpty == false
  }
}
