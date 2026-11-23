import AppKit
import LociModel
import SwiftUI

/// The panel a video, episode or media file waits in before it is taken in: what it is, how to keep it,
/// where its transcript comes from, whether to translate it, and a line for why. It opens at once with
/// placeholders and fills in when the link has been read. A link already in the library shows only that item.
struct ImportSheet: View {
  @Environment(\.host) private var host
  @Environment(\.showFailure) private var showFailure
  let pending: PendingImport
  let close: () -> Void
  /// Opens the item over where the window is.
  let open: (EntityID) -> Void
  @State private var reading: Reading = .waiting
  @State private var draft: ImportDraft?
  @State private var why = ""
  @State private var setup: Feed<MediaSetup>?
  @State private var shown = false

  /// What has been read behind the link.
  enum Reading: Equatable {
    case waiting
    case media(MediaPreview)
    case saved(Item)
    /// The link could not be read now; it is taken in all the same and read again by its job.
    case unread
  }

  var body: some View {
    ZStack {
      Palette.scrim.contentShape(Rectangle()).ignoresSafeArea()
      sheet
        .scaleEffect(shown ? 1 : 0.94)
        .offset(y: shown ? 0 : 10)
        .opacity(shown ? 1 : 0)
    }
    .onExitCommand(perform: close)
    .onAppear { withAnimation(.spring(duration: 0.45, bounce: 0.28)) { shown = true } }
    .subscribing(MediaSettings(), into: $setup)
    .task { await load() }
  }

  private var sheet: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      ImportHeader(pending: pending, reading: reading)
      if case .saved = reading {
        EmptyView()
      } else if let draft = Binding($draft) {
        WhyField(text: $why)
        ViewThatFits(in: .vertical) {
          steps(draft)
          ScrollView { steps(draft) }.scrollIndicators(.never)
        }
      }
      footer
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, Spacing.m)
    .frame(width: Size.importSheetWidth)
    .solidGlass(in: RoundedRectangle(cornerRadius: Radius.importSheet, style: .continuous))
    .background {
      SoftShadow(
        shape: RoundedRectangle(cornerRadius: Radius.importSheet, style: .continuous), opacity: 0.28, radius: 40, y: 24)
    }
    .padding(.vertical, Spacing.l)
    .animation(Motion.standard, value: reading)
  }

  private func steps(_ draft: Binding<ImportDraft>) -> some View {
    ImportSteps(
      draft: draft, media: mediaStep, setup: setup?.value,
      offersSubtitles: !(draft.wrappedValue.offered.isEmpty))
  }

  /// The video or audio step, with the sizes read; files on this Mac have none.
  private var mediaStep: ImportSteps.Media? {
    switch (pending, reading) {
    case (.files, _): nil
    case (.links, _): .init(isAudio: false, sizes: [:])
    case (.link, .media(let media)): .init(isAudio: media.isAudio, sizes: media.sizes)
    case (.link(let url), _): .init(isAudio: LinkKind(url) == .audio, sizes: [:])
    }
  }

  private var footer: some View {
    HStack(spacing: Spacing.xs) {
      if case .saved = reading {
        Spacer()
      } else {
        HStack(spacing: 6) {
          Image(systemName: Symbols.disk).font(.system(size: 12))
          Text(verbatim: total)
        }
        .font(Typography.clock)
        .foregroundStyle(Palette.inkMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Button(action: close) { Text(.loci("dialog.cancel")) }
        .buttonStyle(QuietButtonStyle())
        .keyboardShortcut(.cancelAction)
      if case .saved(let item) = reading {
        Button {
          close()
          open(item.id)
        } label: {
          Text(.loci("import.open"))
        }
        .buttonStyle(AmberButtonStyle())
        .keyboardShortcut(.defaultAction)
      } else {
        Button(action: add) { Text(.loci("import.add")) }
          .buttonStyle(AmberButtonStyle())
          .keyboardShortcut(.defaultAction)
          .disabled(draft == nil)
          .changesData()
      }
    }
    .padding(.top, 2)
  }

  /// The space taking it in uses, or a dash while that cannot be told.
  private var total: String {
    guard let draft else { return "—" }
    let missing = setup?.value?.speechModels.first { $0.model == draft.recognizing.model }?.state != .ready
    let media: MediaPreview? = if case .media(let media) = reading { media } else { nil }
    let sizes = media?.sizes ?? (isFiles ? nil : [:])
    let isAudio = media?.isAudio ?? false
    guard let bytes = draft.bytes(sizes: sizes, isAudio: isAudio, missingModel: setup != nil && missing) else {
      return "—"
    }
    return bytes == 0 ? "0 MB" : SpeechModel.bytes(bytes)
  }

  private var isFiles: Bool {
    if case .files = pending { true } else { false }
  }

  private func load() async {
    let model = setup?.value?.speechModel ?? .recommended
    let choice =
      (try? await host.run(ReadImportChoice())) ?? .first(readerLanguage: Self.readerLanguage, speechModel: model)
    draft = ImportDraft(choice, speechModel: model, readerLanguage: Self.readerLanguage)
    guard case .link(let url) = pending else { return }
    let read: Reading
    do throws(HostError) {
      switch try await host.run(ProbeLink(url: url)) {
      case .saved(let item): read = .saved(item)
      case .media(let media): read = .media(media)
      }
    } catch {
      read = .unread
    }
    guard !Task.isCancelled else { return }
    if case .media(let media) = read {
      draft = ImportDraft(
        choice, offered: media.subtitles, spoken: media.spokenSubtitles, speechModel: model,
        readerLanguage: Self.readerLanguage)
    }
    reading = read
  }

  private func add() {
    guard let choice = draft?.choice else { return }
    let why = why
    let pending = pending
    close()
    Task {
      do throws(HostError) {
        switch pending {
        case .link(let url):
          _ = try await host.run(AddLink(url: url, choice: choice, why: why))
        case .links(let urls):
          for url in urls { _ = try await host.run(AddLink(url: url, choice: choice, why: why)) }
        case .files(let files):
          for file in files {
            let upload = try await host.upload(LocalFile(file))
            _ = try await host.run(ImportMediaFile(upload: upload, mode: .copy, choice: choice, why: why))
          }
        }
      } catch {
        showFailure(error)
      }
    }
  }

  /// The language this Mac reads in, as a BCP 47 tag, for a translation not chosen before.
  static var readerLanguage: String {
    guard let first = Locale.preferredLanguages.first else { return "en" }
    let language = Locale(identifier: first).language
    let parts = [language.languageCode?.identifier, language.script?.identifier].compactMap { $0 }
    return parts.isEmpty ? "en" : parts.joined(separator: "-")
  }
}
