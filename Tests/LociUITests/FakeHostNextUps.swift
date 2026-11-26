import LociModel

/// The next-up cards the test gave: the chat's deck has them all, a project's only its own. What is done with
/// them is accepted and forgotten.
extension FakeHost {
  func nextUps(of home: Home) async throws(HostError) -> [NextUp] {
    home == .chat ? nextUps : nextUps.filter { $0.home == home }
  }

  func addNextUp(_ command: AddNextUp) async throws(HostError) -> NextUp { throw .invalidRequest("not here") }
  func proposeApproval(_ command: ProposeApproval) async throws(HostError) -> NextUp {
    throw .invalidRequest("not here")
  }
  func addNextUpCondition(_ command: AddNextUpCondition) async throws(HostError) -> NextUpCondition {
    throw .invalidRequest("not here")
  }
  func nextUpConditions(of home: Home) async throws(HostError) -> [NextUpCondition] { [] }
  func removeNextUpCondition(_ command: RemoveNextUpCondition) async throws(HostError) -> Done { Done() }
  func startNextUp(_ command: StartNextUp) async throws(HostError) -> Done { Done() }
  func setNextUp(_ command: SetNextUp) async throws(HostError) -> NextUp {
    guard let card = nextUps.first(where: { $0.id == command.card }) else { throw .notFound("card") }
    return card
  }
  func approveNextUp(_ command: ApproveNextUp) async throws(HostError) -> Done { Done() }
  func undoApproval(_ command: UndoApproval) async throws(HostError) -> Done { Done() }
}
