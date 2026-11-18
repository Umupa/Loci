import AppKit
import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// Asks the person for a picture in a format Loci keeps; `nil` when they cancel.
struct ChoosePicture {
  let action: @MainActor () async -> URL?

  @MainActor func callAsFunction() async -> URL? {
    await action()
  }

  /// The system's open panel.
  static let panel = ChoosePicture {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = Avatar.formats.compactMap { UTType(filenameExtension: $0) }
    panel.allowsMultipleSelection = false
    return await panel.begin() == .OK ? panel.url : nil
  }
}

extension EnvironmentValues {
  /// Tests put their own in its place.
  @Entry var choosePicture = ChoosePicture.panel
}

/// Loci's face, large, ringed and lifted off the page, with a button in its corner that changes it.
struct Portrait: View {
  @Environment(\.host) private var host
  @Environment(\.choosePicture) private var choosePicture
  @Environment(\.showFailure) private var showFailure
  @Environment(\.lociFace) private var face
  @State private var hovering = false

  var body: some View {
    LociAvatar(size: Self.side, framing: .portrait)
      .background {
        Circle()
          .fill(Palette.canvas)
          .padding(-4)
          .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: 1).padding(-5))
          .shadow(color: Palette.portraitShadow.opacity(0.18), radius: 20, y: 18)
      }
      .overlay(alignment: .bottomTrailing) { change.padding(Spacing.xxs) }
      .contextMenu {
        if face != .drawn {
          Button {
            Task { _ = try? await host.run(ResetAvatar()) }
          } label: {
            Text(.loci("loci.resetFace"))
          }
          .changesData()
        }
      }
  }

  static let side: CGFloat = 168

  private var change: some View {
    Button(action: choose) {
      Image(systemName: Symbols.camera)
        .font(.system(size: 14))
        .foregroundStyle(Palette.ink)
        .frame(width: 34, height: 34)
        .glassEffect(.regular, in: .circle)
        .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(Motion.arrive, value: hovering)
    }
    .buttonStyle(.plain)
    .changesData()
    .onHover { hovering = $0 }
    .help(Text(.loci("loci.changeFace")))
    .accessibilityLabel(Text(.loci("loci.changeFace")))
  }

  private func choose() {
    Task {
      guard let url = await choosePicture() else { return }
      do throws(HostError) {
        _ = try await host.run(SetAvatar(try Self.avatar(at: url)))
      } catch {
        showFailure(error)
      }
    }
  }

  /// The picture at `url` as Loci keeps it, refused when it is unreadable or larger than Loci allows.
  static func avatar(at url: URL) throws(HostError) -> Avatar {
    do {
      return try Avatar(data: Data(contentsOf: url), format: url.pathExtension.lowercased())
    } catch {
      throw .invalidRequest(String(describing: error))
    }
  }
}
