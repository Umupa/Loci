import LociModel
import PDFKit
import SwiftUI

/// A paper as its PDF, with Loci's panel beside it as for an article. Where the reader
/// was is kept by page.
struct PaperScreen: View {
  @Environment(\.host) private var host
  let page: ItemPage
  @State private var document: PDFDocument?
  @State private var job: Feed<Job?>?
  @State private var notes: Feed<[Note]>?
  @State private var tab = SideTab.conversation
  @State private var draft: PassageDraft?
  @AppStorage(PanelMemory.key) private var panelShown = PanelMemory.shownAtFirst

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
          content: .item(page.item.id),
          notes: (notes?.value ?? []).map { PlacedNote(note: $0, range: NSRange(location: 0, length: 0)) },
          keyPoints: nil, openKeyPoint: nil, tab: $tab, draft: $draft, chosen: nil, reveal: { _ in },
          revealPassage: { _ in }, ask: { _ in },
          collapse: { withAnimation(Motion.fold) { panelShown = false } }
        )
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
    .subscribing(NotesOn(content: .item(page.item.id)), into: $notes)
    .task(id: [job?.value == nil]) { await load() }
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
