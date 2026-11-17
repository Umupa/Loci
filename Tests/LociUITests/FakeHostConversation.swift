import LociModel

extension FakeHost {
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done { Done() }
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done { Done() }
  func answerPermission(_ command: AnswerPermission) async throws(HostError) -> Done { Done() }
  func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done { Done() }
  func askAboutPassage(_ command: AskAboutPassage) async throws(HostError) -> EntityID { command.note ?? EntityID() }

  func conversation(of mentor: EntityID) async throws(HostError) -> Conversation {
    Conversation(mentor: mentor, messages: [], turn: nil)
  }

  func pendingAnswers(on content: ContentRef) async -> [PendingAnswer] { [] }
}
