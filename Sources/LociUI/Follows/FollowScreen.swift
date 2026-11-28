import AppKit
import LociModel
import SwiftUI

/// A follow page: the follow's picture grown from the row, its name, and its episodes newest first. Episodes out
/// since the page was last opened have an amber dot; one in the library has an amber tick and opens it; any
/// other is taken in through the import card.
struct FollowScreen: View {
  @Environment(\.host) private var host
  @Environment(\.flights) private var flights
  @Environment(\.webPictures) private var pictures
  @Environment(\.deletions) private var deletions
  @Environment(\.undoManager) private var undoManager
  @Environment(\.showFailure) private var showFailure
  @Environment(\.dismiss) private var dismiss
  let follow: EntityID
  @State private var feed: Feed<FollowPage?>?
  /// When the page was opened before this time, so what came since keeps its dot while the page is up.
  @State private var seenBefore: Timestamp?
  @State private var kept: Set<EpisodeKey>?
  @State private var reading = false

  var body: some View {
    Group {
      if let page = feed?.value ?? nil {
        content(page)
      } else {
        Palette.canvas
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.canvas)
    .subscribing(OneFollow(follow), into: $feed)
    .task { await refresh(again: false) }
    .onChange(of: feed?.value??.follow.opened, initial: true) { _, opened in
      guard let opened, seenBefore == nil else { return }
      seenBefore = opened
      Task { _ = try? await host.run(SawFollow(follow)) }
    }
    .onChange(of: keptNow) { before, after in tookIn(after.subtracting(before)) }
    .onChange(of: gone) { if gone { dismiss() } }
    .onDisappear(perform: flyBack)
  }

  private func content(_ page: FollowPage) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        FollowHead(follow: page.follow, stop: { stop(page.follow) })
        if let problem = page.problem {
          FollowTrouble(problem: problem, reading: reading) { Task { await refresh(again: true) } }
            .padding(.top, Spacing.m)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        FollowEntries(page: page, seenBefore: seenBefore ?? page.follow.opened)
          .padding(.top, Spacing.l)
      }
      .frame(maxWidth: 1040, alignment: .leading)
      .padding(.horizontal, 40)
      .padding(.top, 56)
      .padding(.bottom, Spacing.xl)
      .frame(maxWidth: .infinity)
      .animation(Motion.standard, value: page.problem)
    }
    .scrollIndicators(.automatic)
    .background(alignment: .top) { FollowWash(picture: page.follow.picture) }
  }

  private var gone: Bool {
    if case .value(let page) = feed, page == nil { return true }
    return false
  }

  private var keptNow: Set<EpisodeKey> {
    Set((feed?.value ?? nil)?.entries.compactMap { $0.item == nil ? nil : $0.episode.key } ?? [])
  }

  /// An episode just taken in falls into its category in the sidebar.
  private func tookIn(_ keys: Set<EpisodeKey>) {
    guard let page = feed?.value ?? nil, kept != nil else {
      kept = keptNow
      return
    }
    kept = keptNow
    let category: LibraryCategory = page.follow.source.isChannel ? .video : .audio
    for entry in page.entries where keys.contains(entry.episode.key) {
      let picture =
        page.follow.source.isChannel
        ? EpisodeThumbnail.image(of: entry.episode, fallback: page.follow.picture, in: pictures)
        : page.follow.picture.flatMap { pictures?.image(of: $0) }
      flights?.launch(
        picture, from: .episode(entry.episode.key), to: .category(category), rounding: (0.06, 0.2), arc: 120)
    }
  }

  private func flyBack() {
    guard let follow = feed?.value ?? nil else { return }
    let rounding = FollowFace.rounding(follow.follow.source.isChannel)
    flights?.launch(
      follow.follow.picture.flatMap { pictures?.image(of: $0) }, from: .followHead(follow.follow.id),
      to: .follow(follow.follow.id), rounding: (rounding, rounding))
  }

  private func refresh(again: Bool) async {
    reading = true
    defer { reading = false }
    _ = try? await host.run(RefreshFollow(follow, again: again))
  }

  private func stop(_ follow: Follow) {
    Task {
      do throws(HostError) {
        let stopped = try await host.run(StopFollowing(follow.id))
        deletions?.happened(.loci("follow.stopped"), action: .loci("follow.stop"), undoManager: undoManager) {
          Task { _ = try? await host.run(RestoreFollowing(stopped)) }
        }
      } catch {
        showFailure(error)
      }
    }
  }
}

/// The top of a follow page: the picture, the name and where it is, and on the right the amber tick that stops
/// following and the way out to the browser.
private struct FollowHead: View {
  @Environment(\.flights) private var flights
  @Environment(\.changesAllowed) private var changesAllowed
  let follow: Follow
  let stop: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.l) {
      FollowFace(picture: follow.picture, isChannel: follow.source.isChannel, side: 112, lifted: true)
        .flightMark(.followHead(follow.id))
        .opacity(flights?.isLanding(on: .followHead(follow.id)) == true ? 0 : 1)
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(serif: follow.name, Typography.preparingTitle)
          .foregroundStyle(Palette.ink)
          .lineLimit(2)
        HStack(spacing: 6) {
          Image(systemName: follow.source.isChannel ? "play.rectangle.fill" : "antenna.radiowaves.left.and.right")
            .font(.system(size: 11))
          handle.font(Typography.mono)
        }
        .foregroundStyle(Palette.inkFaint)
      }
      Spacer(minLength: Spacing.m)
      HStack(spacing: Spacing.xs) {
        if changesAllowed { FollowingButton(stop: stop) }
        Link(destination: follow.page) {
          Image(systemName: Symbols.external)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.inkMuted)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Palette.fill))
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(Text(.loci("follow.openInBrowser")))
      }
    }
  }

  private var handle: Text {
    if let handle = follow.handle { return Text(verbatim: handle) }
    switch follow.source {
    case .youtube: return Text(.loci("follow.platformYoutube"))
    case .xiaoyuzhou: return Text(.loci("follow.platformXiaoyuzhou"))
    case .apple: return Text(.loci("follow.platformApple"))
    case .feed: return Text(.loci("follow.platformFeed"))
    }
  }
}

/// The amber tick that says the follow is on; under the pointer it turns red and stops it.
private struct FollowingButton: View {
  let stop: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: stop) {
      Image(systemName: hovering ? Symbols.cancel : Symbols.done)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(hovering ? Palette.onAccent : Palette.accentInk)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 34, height: 34)
        .background(Circle().fill(hovering ? Palette.failure : Palette.accent))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle())
    .onHover { hovering = $0 }
    .animation(Motion.quick, value: hovering)
    .help(Text(.loci("follow.stop")))
  }
}

/// Why the episodes could not be read, with a way to try again.
private struct FollowTrouble: View {
  let problem: FollowProblem
  let reading: Bool
  let retry: () -> Void

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: Symbols.problem).font(.system(size: 12)).foregroundStyle(Palette.failure)
      Text(.loci("follow.unread")).font(Typography.bodyEmphasis).foregroundStyle(Palette.ink)
      Text(verbatim: "·").foregroundStyle(Palette.inkFaint)
      Text(Self.reason(problem)).font(Typography.body).foregroundStyle(Palette.inkMuted)
      Button(action: retry) {
        Image(systemName: Symbols.reload)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Palette.inkMuted)
          .rotationEffect(.degrees(reading ? 360 : 0))
          .animation(reading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: reading)
          .frame(width: 26, height: 26)
          .background(Circle().fill(Palette.fill))
          .contentShape(Circle())
      }
      .buttonStyle(PressStyle())
      .disabled(reading)
      .help(Text(.loci("follow.retry")))
    }
  }

  static func reason(_ problem: FollowProblem) -> LocalizedStringResource {
    switch problem {
    case .signIn: .loci("follow.problemSignIn")
    case .gone: .loci("follow.problemGone")
    case .refused: .loci("follow.problemRefused")
    case .offline: .loci("follow.problemOffline")
    }
  }
}

/// The follow's colors behind the top of its page, fading into the canvas.
private struct FollowWash: View {
  @Environment(\.webPictures) private var pictures
  @Environment(\.colorScheme) private var colorScheme
  let picture: URL?

  var body: some View {
    if let image = picture.flatMap({ pictures?.image(of: $0) }), let wash = CoverWash.of(image) {
      Image(nsImage: wash)
        .resizable()
        .frame(height: 360)
        .blur(radius: 40)
        .opacity(colorScheme == .dark ? 0.42 : 0.32)
        .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .transition(.opacity)
    }
  }
}
