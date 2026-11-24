import Foundation
import LociModel

enum CodexCommand {
  static func request(_ method: String, params: JSONValue, id: String) -> JSONValue {
    .object(["id": .string(id), "method": .string(method), "params": params])
  }

  static func reply(_ id: JSONValue, result: JSONValue) -> JSONValue {
    .object(["id": id, "result": result])
  }
}
