import LociModel

/// Every kind of call Loci makes to a model, and what each runs on. What talks runs on the runtime of the
/// conversation it belongs to; what does not talk runs on the tool model. A new kind does not compile until it
/// says which.
enum ModelWork {
  /// Calls that open an agent session.
  enum Session: Sendable {
    /// A turn in a conversation; writing a course is a turn in its conversation.
    case turn(ConversationRef)
    /// What came of a follow-up, said in the conversation that set it.
    case followUp(setIn: ConversationRef)
    /// Mending a source; what was mended is said in the conversation of its home.
    case repair(SourceKey)
    /// The daily review of the chat's memory, or of a project's.
    case review(Home)
    /// Panels' refreshes and schedules, which only update panels and notes.
    case refresh

    var runsOn: SessionEngine {
      switch self {
      case .turn(let conversation), .followUp(let conversation): .conversation(conversation)
      case .repair(let source): .conversation(source.home.conversation)
      case .review(let home): .conversation(home.conversation)
      case .refresh: .toolModel
      }
    }
  }

  /// Calls that ask a model service once, with no agent.
  enum Request: Sendable {
    case translation, chapters, keyPoints, tidying, speakerNames

    var model: ModelUse {
      switch self {
      case .translation: .translation
      case .chapters, .keyPoints, .tidying, .speakerNames: .tool
      }
    }

    /// What happens while the model services offer no model for it.
    var withoutModel: WithoutModel {
      switch self {
      case .translation, .chapters, .keyPoints, .tidying: .waitForSetup
      case .speakerNames: .mainConversation
      }
    }
  }
}

/// What a session runs on.
enum SessionEngine: Equatable, Sendable {
  /// The runtime of the conversation.
  case conversation(ConversationRef)
  /// The bundled Pi with the tool model, with Loci's tools; the main conversation's runtime while there is no tool
  /// model or the bundled Pi is still downloading.
  case toolModel
}

/// What a request does while the model services offer no model for it.
enum WithoutModel: Sendable {
  /// It waits for the model services to be set up.
  case waitForSetup
  /// It asks the main conversation's runtime in a one-off session instead.
  case mainConversation
}
