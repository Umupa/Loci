import LociModel

extension LocalHost {
  public func sendMessage(_ command: SendMessage) async throws(HostError) -> Done {
    throw .invalidRequest("conversations arrive with the mentor runtime")
  }

  public func stopTurn(_ command: StopTurn) async throws(HostError) -> Done {
    Done()
  }

  public func answerPermission(_ command: AnswerPermission) async throws(HostError) -> Done {
    Done()
  }

  public func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done {
    throw .invalidRequest("conversations arrive with the mentor runtime")
  }

  public func askAboutPassage(_ command: AskAboutPassage) async throws(HostError) -> EntityID {
    throw .invalidRequest("conversations arrive with the mentor runtime")
  }

  public func conversation(of mentor: EntityID) async throws(HostError) -> Conversation {
    Conversation(mentor: mentor, messages: [], turn: nil)
  }

  public func pendingAnswers(on content: ContentRef) async -> [PendingAnswer] {
    []
  }
}
