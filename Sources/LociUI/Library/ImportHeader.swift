import AppKit
import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// The top of the import panel: the cover, the title in the serif, and the channel and length. While the link
/// is being read, shimmering placeholders stand in their places.
struct ImportHeader: View {
  let pending: PendingImport
  let reading: ImportSheet.Reading

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      art
        .frame(width: Size.importCover.width, height: Size.importCover.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(
            Palette.lineStrong, lineWidth: Size.hairline)
        }
        .background {
          SoftShadow(shape: RoundedRectangle(cornerRadius: 9, style: .continuous), opacity: 0.1, radius: 6, y: 3)
        }
      VStack(alignment: .leading, spacing: 7) {
        if let heading {
          heading
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
          if !details.isEmpty { meta.transition(.opacity) }
        } else {
          Shimmer().frame(height: 18).frame(maxWidth: .infinity)
          Shimmer().frame(width: 180, height: 18)
          Shimmer().frame(width: 110, height: 12).padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var heading: Text? {
    let face = Serif.Face(size: 18, weight: .semibold)
    if case .files(let files) = pending, files.count > 1 {
      return Text(.loci("import.files \(files.count)")).font(face.latin)
    }
    if case .links(let links) = pending {
      return Text(.loci("import.videos \(links.count)")).font(face.latin)
    }
    return title.map { Text(serif: $0, face) }
  }

  private var title: String? {
    switch (pending, reading) {
    case (.files(let files), _):
      files.first?.deletingPathExtension().lastPathComponent
    case (_, .media(let media)): media.title
    case (_, .saved(let item)): item.title
    case (.link(let url), .unread): url.host().map { $0.replacing(/^www\./, with: "") } ?? url.absoluteString
    case (.link, .waiting), (.links, _): nil
    }
  }

  @ViewBuilder private var meta: some View {
    HStack(spacing: 6) {
      Image(systemName: Symbols.kind(kind)).font(.system(size: 11))
      Text(verbatim: details.joined(separator: " · "))
    }
    .font(Typography.clock)
    .foregroundStyle(Palette.inkMuted)
    .lineLimit(1)
  }

  private var kind: ItemKind {
    switch (pending, reading) {
    case (_, .media(let media)): media.isAudio ? .audio : .video
    case (_, .saved(let item)): ItemKind(item.kind)
    case (.files(let files), _): files.allSatisfy(Self.isAudio) ? .audio : .video
    case (.link(let url), _): LinkKind(url) == .audio ? .audio : .video
    case (.links, _): .video
    }
  }

  private var details: [String] {
    switch (pending, reading) {
    case (_, .media(let media)):
      [media.site, media.duration.map(MediaTime.text)].compactMap { $0 }
    case (_, .saved(let item)):
      [item.site, Self.length(of: item).map(MediaTime.text)].compactMap { $0 }
    case (.files(let files), _):
      [files.count == 1 ? files[0].pathExtension.uppercased() : nil, Self.size(of: files).map(SpeechModel.bytes)]
        .compactMap { $0 }
    case (.link(let url), _):
      [url.absoluteString]
    case (.links(let links), _):
      [Set(links.compactMap { $0.host()?.replacing(/^www\./, with: "") }).sorted().joined(separator: ", ")]
    }
  }

  @ViewBuilder private var art: some View {
    switch reading {
    case .media(let media):
      if let data = media.cover, let image = NSImage(data: data) {
        CoverArt(image: image, square: media.isAudio)
      } else {
        placeholder(Symbols.kind(kind))
      }
    case .saved(let item):
      Cover(item: item, corner: 9)
    case .waiting:
      switch pending {
      case .files: placeholder(Symbols.recognizing)
      case .links: placeholder(Symbols.kind(.video))
      case .link: Shimmer()
      }
    case .unread:
      placeholder(Symbols.kind(kind))
    }
  }

  private func placeholder(_ symbol: String) -> some View {
    Rectangle().fill(Palette.coverBackdrop)
      .overlay {
        Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Palette.inkFaint)
      }
  }

  static func length(of item: Item) -> Duration? {
    switch item.kind {
    case .video(let duration), .audio(let duration): duration
    case .article, .paper, .repository: nil
    }
  }

  static func isAudio(_ file: URL) -> Bool {
    UTType(filenameExtension: file.pathExtension)?.conforms(to: .audio) == true
  }

  /// `nil` when none of the files can be measured.
  static func size(of files: [URL]) -> Int64? {
    let sizes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
    return sizes.isEmpty ? nil : Int64(sizes.reduce(0, +))
  }
}

/// A picture read with the link: a video's frame fills the box; an episode's square art sits on a blurred
/// wash of itself.
private struct CoverArt: View {
  let image: NSImage
  let square: Bool

  var body: some View {
    if square {
      GeometryReader { frame in
        ZStack {
          Image(nsImage: image).resizable().scaledToFill()
            .frame(width: frame.size.width * 1.3, height: frame.size.height * 1.3)
            .blur(radius: 14).saturation(1.3).brightness(-0.12)
          Image(nsImage: image).resizable().scaledToFill()
            .frame(width: frame.size.height * 0.84, height: frame.size.height * 0.84)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .background {
              SoftShadow(shape: RoundedRectangle(cornerRadius: 4, style: .continuous), opacity: 0.35, radius: 5, y: 2)
            }
        }
        .frame(width: frame.size.width, height: frame.size.height)
      }
    } else {
      Image(nsImage: image).resizable().scaledToFill()
    }
  }
}

/// A placeholder with light passing over it, for something still being read. Held still in snapshots.
struct Shimmer: View {
  @Environment(\.standIns) private var standIns

  var body: some View {
    TimelineView(.animation(paused: standIns != nil)) { context in
      let phase =
        standIns == nil ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 : 0.35
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(
          LinearGradient(
            stops: [
              .init(color: Palette.fill, location: 0), .init(color: Palette.fillStrong, location: 0.5),
              .init(color: Palette.fill, location: 1),
            ],
            startPoint: UnitPoint(x: -1 + phase * 3, y: 0.5), endPoint: UnitPoint(x: phase * 3, y: 0.5))
        )
    }
  }
}

/// The line in the import panel for why something is taken in, in the serif's italic.
struct WhyField: View {
  @Binding var text: String

  var body: some View {
    let prompt = Text(.loci("import.why"))
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: Symbols.why)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(text.isEmpty ? Palette.inkFaint : Palette.accent)
      TextField(text: $text, prompt: prompt.foregroundStyle(Palette.inkFaint), axis: .vertical) { prompt }
        .textFieldStyle(.plain)
        .font(.system(size: 14, design: .serif).italic())
        .foregroundStyle(Palette.ink)
        .lineLimit(1...3)
    }
    .padding(.horizontal, Spacing.s)
    .padding(.vertical, 9)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fill))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line, lineWidth: Size.hairline)
    }
  }
}
