import AppKit
import LociModel
import SwiftUI

/// The card a channel, show or feed link brings up under the link field: who it is and the latest three, then
/// Follow, or Open when it is followed already. It opens at once with placeholders and fills in as it is read.
struct FollowCard: View {
  @Environment(\.host) private var host
  @Environment(\.flights) private var flights
  @Environment(\.webPictures) private var pictures
  @Environment(\.openPage) private var openPage
  @Environment(\.showFailure) private var showFailure
  let link: URL
  let close: () -> Void
  @State private var preview: FollowPreview?
  @State private var failure: LocalizedStringResource?
  @State private var shown = false
  @State private var following = false

  static let width: CGFloat = 480

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      who
      if let failure {
        Text(failure).font(Typography.body).foregroundStyle(Palette.inkMuted).lineLimit(3)
      } else {
        latest
      }
      footer
    }
    .padding(20)
    .frame(width: Self.width)
    .solidGlass(in: RoundedRectangle(cornerRadius: Radius.importSheet, style: .continuous))
    .background {
      SoftShadow(
        shape: RoundedRectangle(cornerRadius: Radius.importSheet, style: .continuous), opacity: 0.24, radius: 32, y: 18)
    }
    .scaleEffect(shown ? 1 : 0.96, anchor: .top)
    .offset(y: shown ? 0 : -6)
    .opacity(shown ? 1 : 0)
    .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.25)) { shown = true } }
    .onExitCommand(perform: close)
    .task(id: link) { await read() }
    .animation(Motion.standard, value: preview)
  }

  private var isChannel: Bool {
    if let preview { return preview.source.isChannel }
    if case .youtube? = FollowLink(link) { return true }
    return false
  }

  private var who: some View {
    HStack(spacing: Spacing.s) {
      FollowFace(picture: preview?.picture, isChannel: isChannel, side: 56)
        .flightMark(.followCard)
      VStack(alignment: .leading, spacing: 4) {
        if let preview {
          Text(serif: preview.name, Typography.mediaTitle).foregroundStyle(Palette.ink).lineLimit(1)
          Text(verbatim: preview.handle ?? preview.page.host() ?? "")
            .font(Typography.mono)
            .foregroundStyle(Palette.inkFaint)
        } else {
          Shimmer().frame(width: 180, height: 20).clipShape(Capsule())
          Shimmer().frame(width: 110, height: 11).clipShape(Capsule())
        }
      }
    }
  }

  private var latest: some View {
    HStack(alignment: .top, spacing: Spacing.s) {
      ForEach(0..<3, id: \.self) { index in
        let episode = preview?.episodes.dropFirst(index).first
        VStack(alignment: .leading, spacing: 6) {
          if isChannel {
            if let episode {
              EpisodeThumbnail(episode: episode, fallback: preview?.picture, width: 140)
            } else {
              Shimmer().frame(width: 140, height: 140 * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            }
          }
          if let episode {
            Text(verbatim: episode.title)
              .font(Typography.body)
              .foregroundStyle(Palette.ink)
              .lineLimit(isChannel ? 2 : 3)
              .fixedSize(horizontal: false, vertical: true)
              .transition(.opacity)
          } else if preview == nil {
            Shimmer().frame(height: 10).clipShape(Capsule())
            Shimmer().frame(width: 84, height: 10).clipShape(Capsule())
          }
        }
        .frame(width: 140, alignment: .leading)
      }
    }
  }

  private var footer: some View {
    HStack(spacing: Spacing.xs) {
      Spacer()
      Button(action: close) { Text(.loci("dialog.cancel")) }
        .buttonStyle(QuietButtonStyle())
        .keyboardShortcut(.cancelAction)
      if let followed = preview?.following {
        Button {
          close()
          openPage(.follow(followed))
        } label: {
          Text(.loci("follow.open"))
        }
        .buttonStyle(AmberButtonStyle())
        .keyboardShortcut(.defaultAction)
      } else if failure == nil {
        Button(action: follow) { Text(.loci("follow.follow")) }
          .buttonStyle(AmberButtonStyle())
          .changesData()
          .keyboardShortcut(.defaultAction)
          .disabled(preview == nil || following)
      }
    }
  }

  private func read() async {
    do throws(HostError) {
      preview = try await host.run(PreviewFollow(link))
    } catch {
      failure = Messages.describe(error)
    }
  }

  /// Follows, and the picture flies into the row.
  private func follow() {
    following = true
    Task {
      do throws(HostError) {
        let follow = try await host.run(StartFollowing(link))
        let rounding = FollowFace.rounding(follow.source.isChannel)
        flights?.launch(
          follow.picture.flatMap { pictures?.image(of: $0) }, from: .followCard, to: .follow(follow.id),
          rounding: (rounding, rounding), arc: 40)
        close()
      } catch {
        following = false
        showFailure(error)
      }
    }
  }
}

/// The follow card hung under the link field, or near the top of the window where there is none. A click
/// anywhere else puts it away.
struct FollowCardLayer: View {
  @Environment(\.flights) private var flights
  let link: URL
  let close: () -> Void

  var body: some View {
    GeometryReader { proxy in
      let window = proxy.frame(in: .global)
      let field = flights?.frame(of: .linkField)
      ZStack(alignment: .topLeading) {
        Color.clear.contentShape(Rectangle()).onTapGesture(perform: close)
        FollowCard(link: link, close: close)
          .offset(
            x: (field?.midX ?? window.midX) - window.midX,
            y: (field.map { $0.maxY + 10 } ?? window.minY + 90) - window.minY
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    }
  }
}

extension EnvironmentValues {
  /// The link the follow card is about while it is up; the link field lights up for it.
  @Entry var followCardLink: URL?
}
