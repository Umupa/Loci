import LociModel
import SwiftUI

/// The videos a channel or list page links to, each with a check; those not yet in the library start checked.
/// One switch checks them all, or clears them all once all are checked.
struct VideoPicker: View {
  let videos: [FoundVideo]
  let library: [Item]
  let download: ([URL]) -> Void
  @State private var chosen: Set<URL>

  init(videos: [FoundVideo], library: [Item], download: @escaping ([URL]) -> Void) {
    self.videos = videos
    self.library = library
    self.download = download
    let had = Set(library.compactMap { $0.source.map(PageAddress.init) })
    _chosen = State(initialValue: Set(videos.map(\.url).filter { !had.contains(PageAddress($0)) }))
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          ForEach(videos) { video in row(video) }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: 420)
      .fixedSize(horizontal: false, vertical: true)
      Rectangle().fill(Palette.lineStrong).frame(height: Size.hairline).padding(.top, Spacing.xxs)
      HStack {
        Button {
          chosen = Self.toggledAll(chosen, of: videos)
        } label: {
          Text(chosen.isSuperset(of: videos.map(\.url)) ? .loci("browser.selectNone") : .loci("browser.selectAll"))
            .font(Typography.button)
            .foregroundStyle(Palette.inkMuted)
            .padding(.horizontal, Spacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        Spacer()
        PrimaryButton(
          action: { download(videos.map(\.url).filter(chosen.contains)) },
          label: {
            Text(
              joining: Text(.loci("browser.downloadSome")), Text(verbatim: " \(chosen.count) "),
              Text(.loci("browser.videos")))
          }
        )
        .disabled(chosen.isEmpty)
        .opacity(chosen.isEmpty ? 0.5 : 1)
      }
      .padding(.horizontal, Spacing.xs)
      .padding(.top, 10)
      .padding(.bottom, 6)
    }
    .padding(6)
    .frame(width: Size.videoPicker)
    .background(
      RoundedRectangle(cornerRadius: Spacing.m, style: .continuous).fill(Palette.floating)
        .shadow(color: .black.opacity(0.28), radius: 30, y: 24)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Spacing.m, style: .continuous).strokeBorder(
        Palette.lineStrong, lineWidth: Size.hairline)
    )
  }

  /// Every video when any is unchecked; none when all are checked.
  nonisolated static func toggledAll(_ chosen: Set<URL>, of videos: [FoundVideo]) -> Set<URL> {
    let all = Set(videos.map(\.url))
    return chosen.isSuperset(of: all) ? [] : all
  }

  private func row(_ video: FoundVideo) -> some View {
    let on = chosen.contains(video.url)
    return Button {
      if on { chosen.remove(video.url) } else { chosen.insert(video.url) }
    } label: {
      HStack(spacing: 10) {
        Check(on: on)
        AsyncImage(url: video.thumbnail) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Palette.coverBackdrop
        }
        .frame(width: Size.pickerThumbnail, height: Size.pickerThumbnail * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
            .strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        VStack(alignment: .leading, spacing: 5) {
          Text(verbatim: video.title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .lineSpacing(1)
          if let duration = video.duration {
            Text(verbatim: duration).font(Typography.mono).foregroundStyle(Palette.inkFaint)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Spacing.xs)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A round check, amber when on.
struct Check: View {
  let on: Bool

  var body: some View {
    ZStack {
      if on {
        Circle().fill(Palette.accent)
        Image(systemName: Symbols.done).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.onAccent)
      } else {
        Circle().strokeBorder(Palette.lineStrong, lineWidth: 1).background(Circle().fill(Palette.thumb))
      }
    }
    .overlay(Circle().strokeBorder(.black.opacity(on ? 0.15 : 0), lineWidth: Size.hairline))
    .frame(width: 18, height: 18)
    .frame(width: 22)
  }
}
