import Foundation

/// Why a value could not be made: one of its type's invariants did not hold.
public struct ModelError: Error, Equatable, CustomStringConvertible {
  public let description: String

  init(_ description: String) {
    self.description = description
  }
}

extension Decoder {
  func validated<Value>(_ build: () throws -> Value) throws -> Value {
    do {
      return try build()
    } catch let error as ModelError {
      throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: error.description))
    }
  }
}
