import Foundation
import LociModel
import LociStore

extension LocalHost {
  public func keyPointsPage(_ id: EntityID) async throws(HostError) -> KeyPointsPage {
    let (keyPoints, settings) = try attempt { (try store.keyPoints(of: id), try store.settings()) }
    let choice = settings.keyPointChoice ?? keyPoints?.choice ?? .standard
    let model = try await library.context.models.options().model(preferring: choice.model, for: .transcripts)
    return KeyPointsPage(keyPoints: keyPoints, picking: await library.picker.picking(id), choice: choice, model: model)
  }

  public func pickKeyPoints(_ command: PickKeyPoints) async throws(HostError) -> Done {
    let item = try attempt { try store.item(command.item) }
    switch item.kind {
    case .article, .video, .audio: break
    case .paper, .repository, .book: throw .invalidRequest("Key points are picked for videos, audio and articles")
    }
    guard try await library.context.models.options().model(preferring: command.choice.model, for: .transcripts) != nil
    else { throw .invalidRequest("No model service is configured to pick key points.") }
    _ = try attempt { try store.changeSettings { $0.keyPointChoice = command.choice } }
    await library.picker.start(command.item, choice: command.choice)
    await follow([.item(command.item)])
    return Done()
  }
}
