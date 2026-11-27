import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// The questions and notices a window can show, one value so the root view keeps them in one place.
struct Dialogs {
  var importing = false
  /// What waits in the import panel.
  var intake: PendingImport?
  /// The channel, show or feed link the follow card is about.
  var following: URL?
  /// What went wrong. A change refused because the Mac is offline is not told: the window already says so.
  var failure: HostError? {
    didSet { if case .offline? = failure { failure = nil } }
  }
  var readingStateLost = false
}

extension View {
  func dialogs(_ dialogs: Binding<Dialogs>, host: any LociModel.Host) -> some View {
    modifier(DialogsModifier(dialogs: dialogs, host: host))
  }
}

private struct DialogsModifier: ViewModifier {
  @Environment(\.changesAllowed) private var changesAllowed
  @Binding var dialogs: Dialogs
  let host: any LociModel.Host

  func body(content: Content) -> some View {
    importing(questions(content))
  }

  private func questions(_ content: Content) -> some View {
    content
      .alert(Text(.loci("dialog.failed")), isPresented: present(\.failure), presenting: dialogs.failure) { _ in
        Button(role: .cancel) {
        } label: {
          Text(.loci("dialog.ok"))
        }
      } message: { failure in
        Text(Messages.describe(failure))
      }
      .alert(Text(.loci("health.readingStateLost")), isPresented: $dialogs.readingStateLost) {
        Button(role: .cancel) {
        } label: {
          Text(.loci("dialog.ok"))
        }
      }
  }

  private func importing(_ content: some View) -> some View {
    content.fileImporter(
      isPresented: $dialogs.importing, allowedContentTypes: [.text, .epub, .audiovisualContent],
      allowsMultipleSelection: true
    ) { result in
      guard changesAllowed else { return }
      let chosen = (try? result.get()) ?? []
      let media = chosen.filter(Dropped.isMedia)
      let books = chosen.filter(Dropped.isBook)
      let files = chosen.filter { !media.contains($0) && !books.contains($0) }.compactMap { try? TextFile(reading: $0) }
      TakeIn(host: host, ask: { dialogs.intake = $0 }, failed: { dialogs.failure = $0 })
        .files(media: media, text: files, books: books)
    }
  }

  private func perform(_ work: @escaping @MainActor () async throws -> Void) {
    Task {
      do {
        try await work()
      } catch let error as HostError {
        dialogs.failure = error
      } catch {
        dialogs.failure = .storage(String(describing: error))
      }
    }
  }

  private func present<Value>(_ field: WritableKeyPath<Dialogs, Value?>) -> Binding<Bool> {
    Binding(get: { dialogs[keyPath: field] != nil }, set: { if !$0 { dialogs[keyPath: field] = nil } })
  }
}
