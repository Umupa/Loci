import LociModel
import SwiftUI
import UniformTypeIdentifiers

/// The questions and notices a window can show, one value so the root view keeps them in one place.
struct Dialogs {
  var deletingItem: Item?
  var importing = false
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
  @Binding var dialogs: Dialogs
  let host: any LociModel.Host

  func body(content: Content) -> some View {
    importing(deleting(questions(content)))
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

  private func deleting(_ content: some View) -> some View {
    content
      .confirmationDialog(
        Text(.loci("item.deleteQuestion")), isPresented: present(\.deletingItem), presenting: dialogs.deletingItem
      ) { item in
        DeleteChoices { notes in
          perform { _ = try await host.run(DeleteItem(item: item.id, notes: notes)) }
        }
      }
  }

  private func importing(_ content: some View) -> some View {
    content.fileImporter(
      isPresented: $dialogs.importing, allowedContentTypes: [.text, .audiovisualContent], allowsMultipleSelection: true
    ) { result in
      let chosen = (try? result.get()) ?? []
      let media = chosen.filter {
        UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audiovisualContent) == true
      }
      let files = chosen.filter { !media.contains($0) }.compactMap { try? TextFile(reading: $0) }
      perform {
        for file in files { _ = try await host.run(AddTextItem(fileName: file.fileName, text: file.text)) }
        for file in media {
          let upload = try await host.upload(LocalFile(file))
          _ = try await host.run(ImportMediaFile(upload: upload, mode: .copy))
        }
      }
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

/// Deleting asks what becomes of the notes on what is deleted.
private struct DeleteChoices: View {
  let choose: (NotesOnDelete) -> Void

  var body: some View {
    Button(role: .destructive) {
      choose(.keep)
    } label: {
      Text(.loci("delete.keepNotes"))
    }
    .changesData()
    Button(role: .destructive) {
      choose(.delete)
    } label: {
      Text(.loci("delete.withNotes"))
    }
    .changesData()
    Button(role: .cancel) {
    } label: {
      Text(.loci("dialog.cancel"))
    }
  }
}
