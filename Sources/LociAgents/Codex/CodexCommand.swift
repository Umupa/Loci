import Foundation

enum CodexCommand {
  static func line(_ record: JSONValue) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(record)
    data.append(0x0A)
    return data
  }

  static func request(_ method: String, params: JSONValue, id: String) -> JSONValue {
    .object(["id": .string(id), "method": .string(method), "params": params])
  }

  static func reply(_ id: JSONValue, result: JSONValue) -> JSONValue {
    .object(["id": id, "result": result])
  }
}
