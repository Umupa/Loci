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
    panel.allowedContentTypes = Set(Avatar.formats.compactMap { UTType(filenameExtension: $0) })
      .sorted { $0.identifier < $1.identifier }
    panel.allowsMultipleSelection = false
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      response = await panel.beginSheetModal(for: window)
    } else {
      response = await panel.begin()
    }
    return response == .OK ? panel.url : nil
  }
}

extension EnvironmentValues {
  /// Tests put their own in its place.
  @Entry var choosePicture = ChoosePicture.panel
}

/// Loci's face, large, ringed and lifted off the page, with its dot. A camera button that changes it shows while
/// the pointer is over the face.
struct Portrait: View {
  @Environment(\.host) private var host
  @Environment(\.choosePicture) private var choosePicture
  @Environment(\.showFailure) private var showFailure
  @Environment(\.lociFace) private var face
  @Environment(\.companionNow) private var now
  @Environment(\.companionFlight) private var flight
  @Environment(\.reducesMotion) private var reduceMotion
  @State private var pointed = false

  var body: some View {
    LociAvatar(size: Self.side, framing: .portrait)
      .background {
        Circle()
          .fill(Palette.canvas)
          .padding(-3)
          .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: 1).padding(-4))
          .shadow(color: Palette.portraitShadow.opacity(0.14), radius: 10, y: 8)
      }
      .flying(.face, in: flight)
      .presenceDot(now.tone, side: Self.side)
      .overlay(alignment: .bottomLeading) {
        change
          .offset(x: -Spacing.xxs, y: Spacing.xxs)
          .opacity(pointed ? 1 : 0)
          .animation(reduceMotion ? nil : Motion.quick, value: pointed)
      }
      .onHover { pointed = $0 }
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

  static let side: CGFloat = 96

  private var change: some View {
    Button(action: choose) {
      Image(systemName: Symbols.camera)
        .font(.system(size: 12))
        .foregroundStyle(Palette.ink)
        .frame(width: 28, height: 28)
        .glassEffect(.regular, in: .circle)
        .overlay(Circle().strokeBorder(Palette.lineStrong, lineWidth: Size.hairline))
        .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
    }
    .buttonStyle(.plain)
    .changesData()
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
