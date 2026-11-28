import Foundation
import LociModel

@testable import LociUI

/// The library's follows, as the test gave them; following, stopping and opening are accepted and forgotten.
extension FakeHost {
  func previewFollow(_ command: PreviewFollow) async throws(HostError) -> FollowPreview { SampleFollows.preview }
  func startFollowing(_ command: StartFollowing) async throws(HostError) -> Follow {
    throw .invalidRequest("not here")
  }
  func stopFollowing(_ command: StopFollowing) async throws(HostError) -> Follow {
    guard let page = library?.follows.first(where: { $0.follow.id == command.follow }) else {
      throw .notFound("follow")
    }
    return page.follow
  }
  func restoreFollowing(_ command: RestoreFollowing) async throws(HostError) -> Done { Done() }
  func sawFollow(_ command: SawFollow) async throws(HostError) -> Done { Done() }
  func refreshFollow(_ command: RefreshFollow) async throws(HostError) -> Done { Done() }
  func followOfItem(_ command: FollowOfItem) async throws(HostError) -> ItemFollow? { nil }
  func listFollows() async throws(HostError) -> [FollowListing] { [] }

  func followSummaries() async throws(HostError) -> [FollowSummary] {
    (library?.follows ?? []).map { page in
      FollowSummary(
        follow: page.follow, latest: page.entries.first?.episode,
        fresh: page.entries.filter { $0.isNew(since: page.follow.opened) }.map(\.episode))
    }
  }

  func followPage(_ follow: EntityID) async throws(HostError) -> FollowPage? {
    library?.follows.first { $0.follow.id == follow }
  }
}
