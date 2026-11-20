import Foundation
import LociModel

extension Store {
  static let importChoiceFile = "import.json"

  /// How the item was taken in; `nil` for an item taken in before choices were kept, which counts as kept on
  /// this Mac, and for one whose file cannot be read.
  public func importChoice(of item: EntityID) throws -> ImportChoice? {
    try existing(itemFolder(item).appending(path: Self.importChoiceFile)).flatMap {
      try? decodeJSON(ImportChoice.self, at: $0)
    }
  }

  public func saveImportChoice(_ choice: ImportChoice, of item: EntityID) throws {
    try write(Formats.document(choice), to: itemFolder(item).appending(path: Self.importChoiceFile))
  }
}
