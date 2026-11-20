import LociModel
import SwiftUI

/// O-S7, O-S8: at the top of the media settings, how much room the media takes: the total over the disk, one
/// bar colored by videos, podcasts and speech models, and under it the videos and episodes with their sizes,
/// each of which can give its room back or be saved again. The models are deleted in the list of speech models.
struct StorageSection: View {
  @Environment(\.host) private var host
  @State private var report: Feed<StorageReport>?
  @State private var items: Feed<[Item]>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let report = report?.value { content(report) }
    }
    .subscribing(StorageUse(), into: $report)
    .subscribing(AllItems(), into: $items)
  }

  private func content(_ report: StorageReport) -> some View {
    Group {
      VStack(alignment: .leading, spacing: 18) {
        summary(report)
        SettingsGroup(title: .loci("storage.items"), inset: 66) {
          ForEach(report.items, id: \.item) { space in
            if let item = byID[space.item] { itemRow(item, space) }
          }
        }
      }
      .changesData()
    }
  }

  private var byID: [EntityID: Item] {
    Dictionary((items?.value ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }

  private func summary(_ report: StorageReport) -> some View {
    let parts: [(LocalizedStringResource, Int64, Color)] = [
      (.loci("storage.video"), report.bytes(of: .video(duration: nil)), Palette.accent),
      (.loci("storage.podcast"), report.bytes(of: .audio(duration: nil)), Palette.Glow.coral),
      (.loci("storage.models"), report.modelBytes, Palette.inkFaint),
    ]
    let used = parts.map(\.1).reduce(0, +)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: Bytes.text(used)).font(.system(size: 28, weight: .semibold)).foregroundStyle(Palette.ink)
        if let capacity = report.capacity {
          Text(verbatim: "/ " + Bytes.text(capacity)).font(.system(size: 13)).foregroundStyle(Palette.inkMuted)
        }
      }
      GeometryReader { frame in
        HStack(spacing: 2) {
          ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
            if part.1 > 0 {
              Rectangle().fill(part.2).frame(
                width: max(frame.size.width * Double(part.1) / Double(max(used, 1)) - 2, 2))
            }
          }
        }
      }
      .frame(height: 8)
      .background(Palette.fillStrong)
      .clipShape(Capsule())
      HStack(spacing: 18) {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
          HStack(spacing: 6) {
            Circle().fill(part.2).frame(width: 8, height: 8)
            Text(part.0).foregroundStyle(Palette.inkMuted)
            Text(verbatim: Bytes.text(part.1)).font(.system(size: 11.5).monospaced()).foregroundStyle(Palette.inkFaint)
          }
        }
      }
      .font(.system(size: 12))
    }
    .padding(.horizontal, 10)
  }

  private func itemRow(_ item: Item, _ space: ItemSpace) -> some View {
    SettingsRow {
      HStack(spacing: 12) {
        GalleryArt(item: item).frame(width: 44, height: 28)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        Text(verbatim: item.title).lineLimit(1).truncationMode(.tail)
      }
      .layoutPriority(1)
    } trailing: {
      HStack(spacing: 12) {
        if let bytes = space.bytes {
          Text(verbatim: Bytes.text(bytes)).font(.system(size: 11.5).monospaced()).foregroundStyle(Palette.inkMuted)
            .fixedSize()
        } else {
          OnlineTag()
        }
        if space.fromLink {
          if space.bytes != nil {
            Button {
              run(FreeMediaSpace(item: item.id))
            } label: {
              Text(.loci("storage.free"))
            }
            .buttonStyle(PushStyle()).fixedSize()
          } else {
            Button {
              run(SaveMediaLocally(item: item.id))
            } label: {
              Text(.loci("storage.save"))
            }
            .buttonStyle(PushStyle()).fixedSize()
          }
        }
      }
    }
  }

  private func run<C: Command>(_ command: C) {
    Task { _ = try? await host.run(command) }
  }
}

/// The label of an item that has no file on the host and plays online.
private struct OnlineTag: View {
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 9, weight: .semibold))
      Text(.loci("storage.online"))
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(Palette.inkMuted)
    .padding(.horizontal, 8)
    .frame(height: 20)
    .background(Capsule().fill(Palette.fillStrong))
    .fixedSize()
  }
}
