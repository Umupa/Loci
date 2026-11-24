import Foundation
import LociModel

extension JSONValue {
  /// The value as one line of JSON Lines: keys sorted, ending in a line feed.
  var line: Data {
    var data = (try? data()) ?? Data()
    data.append(0x0A)
    return data
  }
}
