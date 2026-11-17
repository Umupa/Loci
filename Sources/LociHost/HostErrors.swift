import LociModel
import LociStore

extension HostError {
  /// The error a caller of the host sees for one raised by the store or the database.
  init(_ error: any Error) {
    switch error {
    case let error as HostError: self = error
    case StoreError.notFound(let what): self = .notFound(what)
    case StoreError.alreadyExists(let id): self = .alreadyExists(id)
    case StoreError.invalid(let problem): self = .invalidFile(problem)
    case StoreError.misplacedNote(let note): self = .invalidRequest("note \(note) points into other content")
    case StoreDatabaseError.misplacedPosition(let position):
      self = .invalidRequest("\(position) points into other content")
    case let error as ModelError: self = .invalidRequest(error.description)
    default: self = .storage(String(describing: error))
    }
  }
}

func attempt<Value>(_ body: () throws -> Value) throws(HostError) -> Value {
  do {
    return try body()
  } catch {
    throw HostError(error)
  }
}
