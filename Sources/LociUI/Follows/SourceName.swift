import LociModel
import SwiftUI

/// The channel or show an item came from, by name. When it can be followed, clicking the name offers to follow
/// it, or to open its follow page once it is followed.
struct SourceName: View {
  @Environment(\.host) private var host
  @Environment(\.openPage) private var openPage
  @Environment(\.showFailure) private var showFailure
  @Environment(\.changesAllowed) private var changesAllowed
  let item: Item
  let name: String
  @State private var follow: ItemFollow?
  @State private var hovering = false

  var body: some View {
    Group {
      if let follow, follow.following != nil || changesAllowed {
        Menu {
          if let followed = follow.following {
            Button(.loci("follow.openPage")) { openPage(.follow(followed)) }
          } else {
            Button(.loci("follow.follow")) { start(follow.link) }
          }
        } label: {
          Text(verbatim: name).underline(hovering, color: Palette.inkFaint)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
      } else {
        Text(verbatim: name)
      }
    }
    .task(id: item.id) { follow = (try? await host.run(FollowOfItem(item.id))) ?? nil }
  }

  private func start(_ link: URL) {
    Task {
      do throws(HostError) {
        let followed = try await host.run(StartFollowing(link))
        follow = ItemFollow(link: link, following: followed.id)
      } catch {
        showFailure(error)
      }
    }
  }
}
