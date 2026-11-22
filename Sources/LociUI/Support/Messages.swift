import Foundation
import LociModel

/// What to say about each kind of thing that went wrong, in the reader's language.
enum Messages {
  static func describe(_ error: HostError) -> LocalizedStringResource {
    switch error {
    case .notFound: .loci("error.notFound")
    case .alreadyExists: .loci("error.alreadyExists")
    case .invalidFile(let problem): describe(problem.kind)
    case .invalidRequest: .loci("error.invalidRequest")
    case .storage: .loci("error.storage")
    case .offline: .loci("error.offline")
    }
  }

  static func describe(_ kind: FileProblem.Kind) -> LocalizedStringResource {
    switch kind {
    case .unreadable: .loci("problem.unreadable")
    case .invalid: .loci("problem.invalid")
    case .duplicateID: .loci("problem.duplicateID")
    case .misplacedNote: .loci("problem.misplacedNote")
    }
  }

  static func name(of category: LibraryCategory) -> LocalizedStringResource {
    switch category {
    case .article: .loci("kind.article")
    case .video: .loci("kind.video")
    case .audio: .loci("kind.audio")
    }
  }
}
