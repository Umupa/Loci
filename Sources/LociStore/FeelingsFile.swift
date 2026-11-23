import Foundation
import LociModel

extension Store {
  static let feelingsFile = "feelings.json"

  /// `agent/feelings.json`; a missing file is a companion that has felt nothing yet.
  public func feelings() throws -> Feelings {
    do {
      return try decodeJSON(Feelings.self, at: agentFolder.appending(path: Self.feelingsFile))
    } catch StoreError.notFound {
      return Feelings()
    }
  }

  public func saveFeelings(_ feelings: Feelings) throws {
    try write(Formats.document(feelings), to: agentFolder.appending(path: Self.feelingsFile))
  }
}
