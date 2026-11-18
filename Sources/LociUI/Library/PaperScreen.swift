import LociModel
import PDFKit
import SwiftUI

/// A paper as its PDF, with the conversation and highlights beside it as for an article. Where the reader
/// was is kept by page.
struct PaperScreen: View {
  @Environment(\.host) private var host
  let page: ItemPage
  @State private var document: PDFDocument?
  @State private var job: Feed<Job?>?
  @State private var companion: Feed<ItemConversation>?
  @State private var mentors: Feed<[Mentor]>?
  @State private var notes: Feed<[Note]>?
  @State private var tab = PanelTab.conversation
  @State private var draft: PassageDraft?
  @State private var panelShown = true

  var body: some View {
    HStack(spacing: 0) {
      Group {
        if let document {
          PaperView(document: document)
        } else {
          FetchingItem(item: page.item, job: job?.value ?? nil)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      if panelShown {
        ReaderPanel(
          content: .item(page.item.id), mentor: nil, conversation: nil, companion: companionPanel,
          notes: (notes?.value ?? []).map { PlacedNote(note: $0, range: NSRange(location: 0, length: 0)) },
          tab: $tab, draft: $draft, chosen: nil, reveal: { _ in }, revealPassage: { _ in }, ask: { _ in },
          collapse: { withAnimation(Motion.fold) { panelShown = false } }
        ) {
          CitingLessons(page: page)
        }
        .frame(width: Size.mediaPanel)
        .transition(.move(edge: .trailing))
      }
    }
    .overlay(alignment: .topTrailing) {
      if !panelShown {
        PanelButton(title: .loci("panel.expand")) { withAnimation(Motion.fold) { panelShown = true } }
          .glassEffect(.regular, in: .capsule)
          .padding(Spacing.s)
      }
    }
    .background(Palette.canvas)
    .subscribing(ItemJob(item: page.item.id), into: $job)
    .subscribing(CompanionConversation(item: page.item.id), into: $companion)
    .subscribing(AllMentors(), into: $mentors)
    .subscribing(NotesOn(content: .item(page.item.id)), into: $notes)
    .task(id: [job?.value == nil]) { await load() }
  }

  private var companionPanel: CompanionPanel? {
    guard let all = mentors?.value, !all.isEmpty else { return nil }
    return CompanionPanel(item: page.item.id, conversation: companion?.value, mentors: all)
  }

  private func load() async {
    guard document == nil, let data = try? await host.run(ReadItemPDF(item: page.item.id)) else { return }
    document = PDFDocument(data: data)
  }
}

/// PDFKit's view of the document, on the page's background.
private struct PaperView: NSViewRepresentable {
  let document: PDFDocument

  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.backgroundColor = Tones.canvas
    view.document = document
    return view
  }

  func updateNSView(_ view: PDFView, context: Context) {
    if view.document !== document { view.document = document }
  }
}
