import Foundation
import LociModel

extension FakeHost {
  func sendMessage(_ command: SendMessage) async throws(HostError) -> Done { Done() }
  func stopTurn(_ command: StopTurn) async throws(HostError) -> Done { Done() }
  func startOver(_ command: StartOver) async throws(HostError) -> Done { Done() }
  func writeLesson(_ command: WriteLesson) async throws(HostError) -> Done { Done() }

  func conversation(of mentor: EntityID) async throws(HostError) -> Conversation {
    let empty = Conversation(mentor: mentor, messages: [], turn: nil)
    return mentor == sample.scheduling.id ? (try? sample.conversation()) ?? empty : empty
  }

  func mind(of mentor: EntityID) async throws(HostError) -> Mind { sample.mind }
}
